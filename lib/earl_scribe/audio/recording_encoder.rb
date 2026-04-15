# frozen_string_literal: true

module EarlScribe
  module Audio
    # Encodes raw PCM audio to AAC via a background ffmpeg subprocess.
    # Writes are queued to avoid blocking the capture read loop.
    class RecordingEncoder
      VALID_FORMATS = %w[f32le s16le].freeze

      # Output path + audio format settings for the AAC encoder
      Config = Struct.new(:path, :channels, :sample_rate, :input_format, keyword_init: true)

      def initialize(path:, channels:, sample_rate:, input_format: "f32le")
        unless VALID_FORMATS.include?(input_format)
          raise ArgumentError, "input_format must be one of #{VALID_FORMATS}, got #{input_format.inspect}"
        end

        @config = Config.new(path: path, channels: channels, sample_rate: sample_rate,
                             input_format: input_format)
        @encoder = nil
        @queue = nil
        @thread = nil
      end

      def start
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        @encoder = IO.popen(["ffmpeg", "-f", @config.input_format, "-ac", @config.channels.to_s,
                             "-ar", @config.sample_rate.to_s, "-i", "pipe:0",
                             "-c:a", "aac", "-b:a", "64k", @config.path], "wb", err: File::NULL)
        @queue = Thread::Queue.new
        @thread = Thread.new { drain }
      end

      def push(data)
        @queue&.push(data)
      end

      def stop
        return unless @queue

        @queue.close
        @thread&.join(5)
      end

      private

      def drain
        while (chunk = @queue.pop)
          @encoder.write(chunk)
        end
        @encoder.close
      rescue IOError => error
        EarlScribe.logger.warn("Recording may be incomplete: #{error.message}")
      end
    end
  end
end
