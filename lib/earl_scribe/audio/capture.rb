# frozen_string_literal: true

module EarlScribe
  module Audio
    # Audio capture subprocess — uses sox/CoreAudio on macOS when available, falls back to ffmpeg/AVFoundation.
    class Capture
      attr_reader :device_index, :device_name, :channels, :sample_rate, :recording_path

      def initialize(device_index:, device_name: nil, channels: 2, sample_rate: 48_000, recording_path: nil)
        @device_index = device_index
        @device_name = device_name
        @channels = channels
        @sample_rate = sample_rate
        @recording_path = recording_path
        @process = nil
      end

      def streaming_command
        device_name && sox_available? ? sox_streaming_command : ffmpeg_streaming_command
      end

      def sox_available?
        return @sox_available if defined?(@sox_available)

        @sox_available = system("which", "sox", out: File::NULL, err: File::NULL)
      end

      def chunked_command(output_dir, chunk_seconds: 10)
        [
          "ffmpeg", "-f", "avfoundation", "-i", ":#{device_index}",
          "-ac", channels.to_s, "-ar", sample_rate.to_s,
          "-f", "segment", "-segment_time", chunk_seconds.to_s,
          "-strftime", "1",
          File.join(output_dir, "%Y%m%d_%H%M%S.wav"),
          *recording_args
        ]
      end

      def start_streaming(&block)
        @process = IO.popen(streaming_command, "rb", err: File::NULL)
        encoder = build_recording_encoder
        encoder&.start
        read_loop do |data|
          encoder&.push(data)
          block.call(f32le_to_s16le(data))
        end
      ensure
        encoder&.stop
        stop
      end

      def start_chunked(output_dir, chunk_seconds: 10, &block)
        cmd = chunked_command(output_dir, chunk_seconds: chunk_seconds)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        @process = IO.popen(cmd, err: File::NULL)
        @poller = ChunkPoller.new(output_dir)
        @poller.poll(&block)
      ensure
        stop
        @poller&.yield_final_chunk(&block)
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

      def sox_streaming_command
        ["sox", "-t", "coreaudio", device_name,
         "-r", sample_rate.to_s, "-c", channels.to_s,
         "-b", "32", "-e", "floating-point", "-t", "raw", "-"]
      end

      def ffmpeg_streaming_command
        ["ffmpeg", "-thread_queue_size", "4096",
         "-f", "avfoundation", "-i", ":#{device_index}",
         "-ac", channels.to_s, "-ar", sample_rate.to_s,
         "-f", "f32le", "-"]
      end

      def recording_args
        return [] unless recording_path

        ["-c:a", "aac", "-b:a", "64k", recording_path]
      end

      def build_recording_encoder
        return unless recording_path

        RecordingEncoder.new(path: recording_path, channels: channels, sample_rate: sample_rate)
      end

      def f32le_to_s16le(data)
        data.unpack("e*").map { |sample| (sample.clamp(-1.0, 1.0) * 32_767).to_i }.pack("s<*")
      end

      def read_loop
        chunk_size = 16_384
        while (data = @process.read(chunk_size))
          break if data.empty?

          yield data
        end
      end
    end
  end
end
