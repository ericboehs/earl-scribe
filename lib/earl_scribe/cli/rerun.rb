# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

require_relative "rerun_audio"
require_relative "rerun_progress"

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
        wav = RerunAudio.normalize_wav(paths[:wav]) || paths[:wav]
        pad = wav == paths[:wav] ? 0.0 : RerunAudio::PAD_SEC
        ok = run_file_pass(wav, paths, opts.merge(time_offset_sec: pad))
        FileUtils.rm_f(wav) if wav != paths[:wav]
        report_timing(wall, paths[:wav]) if ok
        ok ? finalize(paths) : restore_live(paths)
      end

      # ffmpeg-rewrite the captured WAV through a standard PCM container with
      # a 1s leading silence pad. Without the pad, Parakeet TDT batch mode
      # consistently drops the first ~20s of audio off the captured WAV — it
      # appears to need a brief warm-up before tracking real content. The
      # pad is trimmed from emitted timestamps via `--batch-pad-sec` so live
      # and rerun timelines stay aligned.
      def normalize_wav(wav)
        return nil unless wav && File.exist?(wav)

        normalized = "#{wav}.norm.wav"
        _out, _err, status = Open3.capture3("ffmpeg", "-y", "-i", wav,
                                            "-af", "adelay=1000|1000",
                                            "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
                                            normalized)
        return normalized if status.success?

        FileUtils.rm_f(normalized)
        nil
      end

      def report_timing(start_time, wav)
        elapsed = Time.now - start_time
        duration = RerunAudio.wav_duration_sec(wav)
        rtfx = duration && elapsed.positive? ? duration / elapsed : nil
        rate = rtfx ? format(" (%<rate>.1fx real-time)", rate: rtfx) : ""
        warn format("rerun done in %<elapsed>.1fs%<rate>s", elapsed: elapsed, rate: rate)
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
        spinner = batch_mode? ? RerunProgress.start_spinner : nil
        stream_to_files(stdout, paths, offset: -opts[:time_offset_sec].to_f)
        spinner&.kill
        RerunProgress.clear if spinner
        stderr_thread.join
        report_status(wait_thr.value, stderr_thread.value)
      end

      def batch_mode?
        Config.rerun_model == "batch"
      end

      def stream_to_files(stdout, paths, offset: 0.0)
        File.open(paths[:jsonl], "w") do |jf|
          File.open(paths[:transcript], "w") do |tf|
            stream_events(stdout, jf, tf, offset: offset)
          end
        end
      end

      def stream_events(stdout, jsonl_file, txt_file, offset: 0.0)
        ctx = { duration: nil, last_paint: 0.0, offset: offset }
        stdout.each_line do |line|
          event = parse_event(line)
          next unless event

          handle_event(event, ctx, jsonl_file, txt_file)
        end
        RerunProgress.clear
      end

      def handle_event(event, ctx, jsonl_file, txt_file)
        case event["type"]
        when "start" then ctx[:duration] = event["audio_duration_sec"]&.to_f
        when "eou" then handle_eou(event, ctx, jsonl_file, txt_file)
        when "final" then ctx[:final] = event
        end
      end

      def handle_eou(event, ctx, jsonl_file, txt_file)
        seg = event_to_segment(event, offset: ctx[:offset])
        jsonl_file.puts(JSON.generate(seg))
        txt_file.puts(format_segment(seg))
        RerunProgress.paint(event["audio_sec"]&.to_f, ctx)
      end

      def report_status(status, stderr_text)
        unless status.success?
          tail = stderr_text.lines.last(3).join.strip
          warn "rerun failed (exit #{status.exitstatus}): #{tail}"
          return false
        end
        true
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

      def event_to_segment(event, offset: 0.0)
        speaker_id = event["speaker"]
        speaker = speaker_id ? "Speaker #{speaker_id}" : "Speaker 0"
        { "speaker" => speaker, "text" => event["text"].to_s,
          "start_time" => [(event["start_sec"].to_f + offset), 0.0].max,
          "end_time" => [(event["audio_sec"].to_f + offset), 0.0].max, "channel" => 0 }
      end

      def format_segment(seg)
        secs = seg["start_time"].to_i
        ts = format("%<h>02d:%<m>02d:%<s>02d", h: secs / 3600, m: (secs % 3600) / 60, s: secs % 60)
        "[#{ts}] #{seg["speaker"]}: #{seg["text"]}"
      end

      def finalize(paths)
        RerunAudio.encode_m4a(paths[:wav], paths[:recording]) if paths[:recording]
        FileUtils.rm_f(paths[:wav])
      end
    end
  end
end
