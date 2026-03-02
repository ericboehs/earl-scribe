# frozen_string_literal: true

require "set"

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

      def start_chunked(output_dir, chunk_seconds: 10, &block)
        cmd = chunked_command(output_dir, chunk_seconds: chunk_seconds)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        @process = IO.popen(cmd, err: File::NULL)
        @yielded = Set.new
        poll_for_chunks(output_dir, &block)
      ensure
        stop
        yield_final_chunk(output_dir, &block)
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

      def poll_for_chunks(output_dir, &block)
        loop do
          yield_completed_chunks(output_dir, &block)
          sleep 0.5
        end
      end

      def yield_completed_chunks(output_dir)
        wavs = Dir.glob(File.join(output_dir, "*.wav")).sort
        wavs[0...-1].each do |path|
          next if @yielded.include?(path)
          next unless File.size?(path)

          @yielded.add(path)
          yield path
        end
      end

      def yield_final_chunk(output_dir)
        Dir.glob(File.join(output_dir, "*.wav")).sort.each do |path|
          next if @yielded&.include?(path)

          yield path if File.size?(path)
        end
      end
    end
  end
end
