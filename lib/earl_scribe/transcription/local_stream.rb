# frozen_string_literal: true

require "open3"

module EarlScribe
  module Transcription
    class LocalStream
      attr_reader :channels, :sample_rate

      CLOSE_READER_TIMEOUT = 30
      CLOSE_STDERR_TIMEOUT = 2

      def initialize(channels: 1, sample_rate: 48_000, asr_bin: nil, chunk_ms: nil)
        raise ArgumentError, "LocalStream requires mono (channels: 1)" unless channels == 1

        @channels = channels
        @sample_rate = sample_rate
        @asr_bin = asr_bin || Config.asr_bin
        @chunk_ms = chunk_ms || Config.asr_chunk_ms
        @parser = LocalStreamEventParser.new
        @subprocess_dead = false
        reset_handles
      end

      def connect(callback)
        cmd = build_command
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(*cmd)
        [@stdin, @stdout, @stderr].each(&:binmode)
        @reader = Thread.new { read_loop(callback) }
        @stderr_drain = Thread.new { drain_stderr }
      rescue Errno::ENOENT
        raise Error, "earl-scribe-asr binary not found at #{@asr_bin.inspect}. " \
                     "Build it with `bin/build-asr` and export EARL_SCRIBE_ASR_BIN."
      rescue Errno::EACCES
        raise Error, "earl-scribe-asr binary at #{@asr_bin.inspect} is not executable. " \
                     "Rebuild via `bin/build-asr`."
      rescue Errno::ENOEXEC
        raise Error, "earl-scribe-asr binary at #{@asr_bin.inspect} is the wrong architecture. " \
                     "Rebuild via `bin/build-asr`."
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
        [@asr_bin, "--stdin", "--stdin-format", stdin_format,
         "--chunk-ms", @chunk_ms.to_s]
      end

      def stdin_format
        sample_rate == 16_000 ? "f32_16k_mono" : "s16_48k_mono"
      end

      private

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
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thr = nil
        @reader = nil
        @stderr_drain = nil
      end
    end
  end
end
