# frozen_string_literal: true

require "open3"

module EarlScribe
  module Transcription
    class LocalStream
      attr_reader :channels, :sample_rate

      CLOSE_READER_TIMEOUT = 30
      CLOSE_STDERR_TIMEOUT = 2

      def initialize(channels: 1, sample_rate: 48_000, asr_bin: nil, chunk_ms: nil,
                     diarize: true, diar: {}, native: nil)
        raise ArgumentError, "LocalStream requires mono (channels: 1)" unless channels == 1

        @channels = channels
        @sample_rate = sample_rate
        @asr_bin = asr_bin || Config.asr_bin
        @chunk_ms = chunk_ms || Config.asr_chunk_ms
        @diarize = diarize
        @diar_debug = diar[:debug] == true
        @diar_variant = diar[:variant]
        @native = native ? { mic: native[:mic] != false } : nil
        @parser = LocalStreamEventParser.new
        @subprocess_dead = false
        reset_handles
      end

      def native?
        !@native.nil?
      end

      # Block until the subprocess exits or the calling thread is interrupted.
      # Native mode owns its own audio capture, so there's no audio loop on the
      # Ruby side — we just wait for SIGINT and forward it to the shim.
      def wait_until_done
        @wait_thr&.join
      rescue Interrupt
        signal_subprocess(:INT)
        @wait_thr&.join
        raise
      end

      def connect(callback)
        cmd = build_command
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(*cmd)
        [@stdin, @stdout, @stderr].each(&:binmode)
        @reader = Thread.new { read_loop(callback) }
        @stderr_drain = Thread.new { drain_stderr }
      rescue Errno::ENOENT, Errno::EACCES, Errno::ENOEXEC => error
        raise Error, "earl-scribe-asr binary at #{@asr_bin.inspect} #{spawn_error_reason(error)}. " \
                     "Rebuild via `bin/build-asr` and set EARL_SCRIBE_ASR_BIN."
      end

      SPAWN_ERROR_REASONS = { Errno::ENOENT => "not found", Errno::EACCES => "is not executable",
                              Errno::ENOEXEC => "is the wrong architecture" }.freeze

      def spawn_error_reason(error)
        SPAWN_ERROR_REASONS.fetch(error.class, "could not be spawned")
      end

      def send_audio(data)
        @stdin&.write(data)
      rescue Errno::EPIPE, IOError
        notify_subprocess_dead
      end

      def close
        @stdin&.close
        warn_if_reader_hung(@reader && !@reader.join(CLOSE_READER_TIMEOUT))
        @stderr_drain&.join(CLOSE_STDERR_TIMEOUT)
        @stdout&.close
        @stderr&.close
        check_exit_status
      ensure
        reset_handles
      end

      def warn_if_reader_hung(hung)
        return unless hung

        EarlScribe.logger.warn("earl-scribe-asr reader did not exit within #{CLOSE_READER_TIMEOUT}s")
      end

      def build_command
        source = @native ? native_args : ["--stdin", "--stdin-format", stdin_format]
        diar = []
        diar << "--no-diarize" unless @diarize
        diar << "--diar-debug" if @diar_debug
        diar += ["--diar-variant", @diar_variant] if @diar_variant
        [@asr_bin, "--chunk-ms", @chunk_ms.to_s, *source, *diar]
      end

      def native_args
        @native[:mic] ? ["--capture"] : ["--capture", "--no-mic"]
      end

      def stdin_format
        sample_rate == 16_000 ? "f32_16k_mono" : "s16_48k_mono"
      end

      private

      def signal_subprocess(sig)
        pid = @wait_thr&.pid
        Process.kill(sig, pid) if pid
      rescue Errno::ESRCH, Errno::EINVAL
        nil
      end

      def notify_subprocess_dead
        return if @subprocess_dead

        @subprocess_dead = true
        EarlScribe.logger.error("earl-scribe-asr subprocess died; dropping subsequent audio")
      end

      def check_exit_status
        status = @wait_thr&.value
        return unless status && !status.success?

        EarlScribe.logger.error("earl-scribe-asr exited #{status.exitstatus || "via signal #{status.termsig}"}")
      end

      def read_loop(callback)
        while (chunk = read_chunk)
          @parser.feed(chunk).each { |event| dispatch(event, callback) }
        end
      rescue IOError
        nil
      rescue StandardError => error
        EarlScribe.logger.error(
          "earl-scribe-asr reader thread crashed: #{error.class}: #{error.message}\n" \
          "#{error.backtrace.first(5).join("\n")}"
        )
        notify_subprocess_dead
      end

      def read_chunk
        @stdout.readpartial(4096)
      rescue EOFError
        nil
      end

      def dispatch(event, callback)
        case event[:event]
        when :eou, :final then callback.call(event[:result]) if event[:result]
        when :error then dispatch_error(event[:data])
        when :malformed then log_malformed(event[:data]["line"].to_s)
        when :noise then EarlScribe.logger.debug("earl-scribe-asr noise: #{event[:data]["line"][0, 200]}")
        end
      end

      def dispatch_error(data)
        EarlScribe.logger.error("earl-scribe-asr reported error: #{data["message"]}")
        notify_subprocess_dead
      end

      def log_malformed(line)
        EarlScribe.logger.error("earl-scribe-asr malformed line (#{line.bytesize}B): #{line[0, 120].inspect}")
      end

      def drain_stderr
        @stderr.each_line do |line|
          EarlScribe.logger.warn("earl-scribe-asr: #{line.chomp}")
        end
      rescue IOError
        nil
      end

      def reset_handles
        @stdin = @stdout = @stderr = @wait_thr = @reader = @stderr_drain = nil
      end
    end
  end
end
