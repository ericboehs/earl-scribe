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
        wav = paths[:wav]
        return unless wav && File.exist?(wav) && File.size(wav) > 44 # > header

        warn "\nRe-transcribing for accuracy... (Ctrl-C to skip)"
        relocate_live(paths)
        run_file_pass(wav, paths, opts) ? finalize(paths) : restore_live(paths)
      rescue Interrupt
        warn "\nrerun skipped; live transcripts kept as final"
        restore_live(paths) if File.exist?(paths[:transcript_live])
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
        out, err, status = Open3.capture3(*cmd)
        unless status.success?
          warn "rerun failed (exit #{status.exitstatus}): #{err.lines.last(3).join.strip}"
          return false
        end
        write_outputs_from_jsonl(out, paths)
        true
      end

      def file_pass_command(wav, opts)
        cmd = [Config.asr_bin, "--file", wav, "--chunk-ms", Config.asr_chunk_ms.to_s]
        cmd += ["--diar-variant", opts[:diar_variant]] if opts[:diar_variant]
        cmd += ["--diar-wait-ms", opts[:diar_wait_ms].to_s] if opts[:diar_wait_ms]
        cmd
      end

      def write_outputs_from_jsonl(stdout, paths)
        File.open(paths[:jsonl], "w") { |jf| File.open(paths[:transcript], "w") { |tf| dump(stdout, jf, tf) } }
      end

      def dump(stdout, jsonl_file, txt_file)
        stdout.each_line do |line|
          event = parse_event(line)
          next unless event && event["type"] == "eou"

          seg = event_to_segment(event)
          jsonl_file.puts(JSON.generate(seg))
          txt_file.puts(format_segment(seg))
        end
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
