# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

module EarlScribe
  module Cli
    # Second-pass rerun against the captured WAV for higher accuracy. Sortformer
    # in --file mode finalizes every frame against the full audio, retroactively
    # cleaning up tentative speakers; sub-second turns that the streaming pass
    # missed get split correctly. The live output is preserved at <base>-live.*.
    module Rerun
      module_function

      def run(paths, opts)
        return unless rerun_ready?(paths[:wav])

        warn "\nRe-transcribing for accuracy... (Ctrl-C to skip)"
        relocate_live(paths)
        execute_pass(paths, opts)
      rescue Interrupt
        warn "\nrerun skipped; live transcripts kept as final"
        restore_live(paths) if File.exist?(paths[:transcript_live])
      end

      def rerun_ready?(wav)
        wav && File.exist?(wav) && File.size(wav) > 44 # > WAV header
      end

      def execute_pass(paths, opts)
        wall = Time.now
        ok = run_file_pass(paths[:wav], paths, opts)
        report_timing(wall, paths[:wav]) if ok
        ok ? finalize(paths) : restore_live(paths)
      end

      def report_timing(start_time, wav)
        elapsed = Time.now - start_time
        duration = wav_duration_sec(wav)
        rtfx = duration && elapsed.positive? ? duration / elapsed : nil
        rate = rtfx ? format(" (%<rate>.1fx real-time)", rate: rtfx) : ""
        warn format("rerun done in %<elapsed>.1fs%<rate>s", elapsed: elapsed, rate: rate)
      end

      # Read RIFF/data chunk sizes from the WAV header to compute audio length.
      # The shim wrote 16k mono Float32 (4 B/sample), so duration = data_bytes / (16k*4).
      def wav_duration_sec(path)
        bytes = File.read(path, 44)
        return nil unless bytes && bytes.bytesize == 44

        data_bytes = bytes[40, 4].unpack1("V")
        data_bytes.to_f / (16_000 * 4)
      end

      def relocate_live(paths)
        FileUtils.mv(paths[:transcript], paths[:transcript_live]) if File.exist?(paths[:transcript])
        FileUtils.mv(paths[:jsonl], paths[:jsonl_live]) if File.exist?(paths[:jsonl])
      end

      def restore_live(paths)
        FileUtils.mv(paths[:transcript_live], paths[:transcript]) if File.exist?(paths[:transcript_live])
        FileUtils.mv(paths[:jsonl_live], paths[:jsonl]) if File.exist?(paths[:jsonl_live])
      end

      def run_file_pass(wav, paths, opts)
        cmd = file_pass_command(wav, opts)
        stdin, stdout, stderr, wait_thr = Open3.popen3(*cmd)
        stdin.close
        stderr_thread = Thread.new { stderr.read }
        stream_to_files(stdout, paths)
        stderr_thread.join
        report_status(wait_thr.value, stderr_thread.value)
      end

      def stream_to_files(stdout, paths)
        File.open(paths[:jsonl], "w") do |jf|
          File.open(paths[:transcript], "w") do |tf|
            stream_events(stdout, jf, tf)
          end
        end
      end

      def stream_events(stdout, jsonl_file, txt_file)
        ctx = { duration: nil, last_paint: 0.0 }
        stdout.each_line do |line|
          event = parse_event(line)
          next unless event

          handle_event(event, ctx, jsonl_file, txt_file)
        end
        $stderr.print("\r\e[K") if progress_tty?
      end

      def handle_event(event, ctx, jsonl_file, txt_file)
        case event["type"]
        when "start" then ctx[:duration] = event["audio_duration_sec"]&.to_f
        when "eou" then handle_eou(event, ctx, jsonl_file, txt_file)
        when "final" then ctx[:final] = event
        end
      end

      def handle_eou(event, ctx, jsonl_file, txt_file)
        seg = event_to_segment(event)
        jsonl_file.puts(JSON.generate(seg))
        txt_file.puts(format_segment(seg))
        paint_progress(event["audio_sec"]&.to_f, ctx)
      end

      def paint_progress(audio_sec, ctx)
        return unless audio_sec && ctx[:duration]&.positive? && progress_tty?
        return if (audio_sec - ctx[:last_paint]).abs < 0.5

        ctx[:last_paint] = audio_sec
        pct = (audio_sec * 100.0 / ctx[:duration]).clamp(0.0, 100.0)
        $stderr.print(format("\r\e[K  rerun [%<bar>s] %<pct>5.1f%% (%<at>6.1f / %<dur>6.1fs)",
                             bar: progress_bar(pct), pct: pct, at: audio_sec, dur: ctx[:duration]))
      end

      def progress_bar(pct, width: 30)
        filled = (width * pct / 100.0).to_i
        ("#" * filled) + ("-" * (width - filled))
      end

      def report_status(status, stderr_text)
        unless status.success?
          tail = stderr_text.lines.last(3).join.strip
          warn "rerun failed (exit #{status.exitstatus}): #{tail}"
          return false
        end
        true
      end

      def progress_tty?
        $stderr.tty?
      end

      def file_pass_command(wav, opts)
        cmd = [Config.asr_bin, "--file", wav]
        cmd << "--batch" if Config.rerun_model == "batch"
        cmd += ["--chunk-ms", Config.rerun_chunk_ms.to_s] unless Config.rerun_model == "batch"
        cmd += ["--diar-variant", opts[:diar_variant]] if opts[:diar_variant]
        cmd += ["--diar-wait-ms", opts[:diar_wait_ms].to_s] if opts[:diar_wait_ms]
        cmd
      end

      def parse_event(line)
        line = line.strip
        return nil if line.empty?

        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def event_to_segment(event)
        speaker_id = event["speaker"]
        speaker = speaker_id ? "Speaker #{speaker_id}" : "Speaker 0"
        { "speaker" => speaker, "text" => event["text"].to_s, "start_time" => event["start_sec"].to_f,
          "end_time" => event["audio_sec"].to_f, "channel" => 0 }
      end

      def format_segment(seg)
        secs = seg["start_time"].to_i
        ts = format("%<h>02d:%<m>02d:%<s>02d", h: secs / 3600, m: (secs % 3600) / 60, s: secs % 60)
        "[#{ts}] #{seg["speaker"]}: #{seg["text"]}"
      end

      def finalize(paths)
        encode_m4a(paths[:wav], paths[:recording]) if paths[:recording]
        FileUtils.rm_f(paths[:wav])
      end

      def encode_m4a(wav, m4a)
        _out, err, status = Open3.capture3("ffmpeg", "-y", "-i", wav, "-c:a", "aac", "-b:a", "96k", m4a)
        return if status.success?

        warn "ffmpeg encode failed: #{err.lines.last(2).join.strip}"
      end
    end
  end
end
