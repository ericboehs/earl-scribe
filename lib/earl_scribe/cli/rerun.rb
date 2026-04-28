# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

require_relative "rerun_audio"
require_relative "rerun_events"
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
        stdin, stdout, stderr, wait_thr = Open3.popen3(*file_pass_command(wav, opts))
        stdin.close
        stderr_thread = Thread.new { stderr.read }
        consume_pass(stdout, paths, opts)
        stderr_thread.join
        report_status(wait_thr.value, stderr_thread.value)
      end

      def consume_pass(stdout, paths, opts)
        spinner = batch_mode? ? RerunProgress.start_spinner : nil
        RerunEvents.stream_to_files(stdout, paths, offset: -opts[:time_offset_sec].to_f)
        spinner&.kill
        RerunProgress.clear if spinner
      end

      def batch_mode?
        Config.rerun_model == "batch"
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

      def finalize(paths)
        RerunAudio.encode_m4a(paths[:wav], paths[:recording]) if paths[:recording]
        FileUtils.rm_f(paths[:wav])
      end
    end
  end
end
