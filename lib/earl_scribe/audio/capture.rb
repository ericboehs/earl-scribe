# frozen_string_literal: true

module EarlScribe
  module Audio
    # FFmpeg subprocess for live audio capture
    class Capture
      attr_reader :device_index, :channels, :sample_rate

      def initialize(device_index:, channels: 2, sample_rate: 16_000)
        @device_index = device_index
        @channels = channels
        @sample_rate = sample_rate
        @process = nil
      end

      def streaming_command
        [
          "ffmpeg", "-f", "avfoundation", "-i", ":#{device_index}",
          "-ac", channels.to_s, "-ar", sample_rate.to_s,
          "-f", "s16le", "-"
        ]
      end

      def chunked_command(output_dir, chunk_seconds: 10)
        [
          "ffmpeg", "-f", "avfoundation", "-i", ":#{device_index}",
          "-ac", channels.to_s, "-ar", sample_rate.to_s,
          "-f", "segment", "-segment_time", chunk_seconds.to_s,
          "-strftime", "1",
          File.join(output_dir, "%Y%m%d_%H%M%S.wav")
        ]
      end

      def start_streaming(&block)
        cmd = streaming_command
        @process = IO.popen(cmd, "rb", err: File::NULL)
        read_loop(&block)
      ensure
        stop
      end

      def stop
        return unless @process

        Process.kill("TERM", @process.pid)
        @process.close
        @process = nil
      rescue Errno::ESRCH, IOError
        @process = nil
      end

      private

      def read_loop
        chunk_size = 4096
        while (data = @process.read(chunk_size))
          break if data.empty?

          yield data
        end
      end
    end
  end
end
