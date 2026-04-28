# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Reads JSONL events from an ASR shim's stdout, parses them, and dispatches
    # to a callback. Lifted out of LocalStream to keep that class focused on
    # subprocess orchestration.
    class LocalStreamReader
      def initialize(stdout:, stderr:, parser:, callback:, on_subprocess_dead:)
        @stdout = stdout
        @stderr = stderr
        @parser = parser
        @callback = callback
        @on_subprocess_dead = on_subprocess_dead
      end

      def read_loop
        while (chunk = read_chunk)
          @parser.feed(chunk).each { |event| dispatch(event) }
        end
      rescue IOError
        nil
      rescue StandardError => error
        log_crash(error)
        @on_subprocess_dead.call
      end

      def drain_stderr
        @stderr.each_line { |line| EarlScribe.logger.warn("earl-scribe-asr: #{line.chomp}") }
      rescue IOError
        nil
      end

      private

      def read_chunk
        @stdout.readpartial(4096)
      rescue EOFError
        nil
      end

      def dispatch(event)
        case event[:event]
        when :eou, :final, :confirmed then @callback.call(event[:result]) if event[:result]
        when :error then dispatch_error(event[:data])
        when :malformed then log_malformed(event[:data]["line"].to_s)
        when :noise then EarlScribe.logger.debug("earl-scribe-asr noise: #{event[:data]["line"][0, 200]}")
        end
      end

      def dispatch_error(data)
        EarlScribe.logger.error("earl-scribe-asr reported error: #{data["message"]}")
        @on_subprocess_dead.call
      end

      def log_malformed(line)
        EarlScribe.logger.error("earl-scribe-asr malformed line (#{line.bytesize}B): #{line[0, 120].inspect}")
      end

      def log_crash(error)
        EarlScribe.logger.error(
          "earl-scribe-asr reader thread crashed: #{error.class}: #{error.message}\n" \
          "#{error.backtrace.first(5).join("\n")}"
        )
      end
    end
  end
end
