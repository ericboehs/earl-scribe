# frozen_string_literal: true

module EarlScribe
  module Audio
    # Encodes raw PCM audio to AAC via a background ffmpeg subprocess.
    # Writes are queued to avoid blocking the capture read loop.
    class RecordingEncoder
      # Output path + audio format settings for the AAC encoder
      Config = Struct.new(:path, :channels, :sample_rate, keyword_init: true)

      def initialize(path:, channels:, sample_rate:)
        @config = Config.new(path: path, channels: channels, sample_rate: sample_rate)
        @encoder = nil
        @queue = nil
        @thread = nil
      end

      def start
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        @encoder = IO.popen(["ffmpeg", "-f", "f32le", "-ac", @config.channels.to_s,
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
