# frozen_string_literal: true

module EarlScribe
  module Audio
    # Captures system audio via the audiotee CLI (Core Audio Taps API, macOS 14.2+).
    # Quacks like Audio::Capture but bypasses device selection entirely.
    class AudioTee
      attr_reader :channels, :sample_rate, :recording_path

      def initialize(channels: 1, sample_rate: 48_000, recording_path: nil)
        @channels = channels
        @sample_rate = sample_rate
        @recording_path = recording_path
        @process = nil
      end

      def streaming_command
        cmd = [Config.audiotee_path, "--sample-rate", sample_rate.to_s]
        cmd << "--stereo" if channels > 1
        cmd
      end

      def start_streaming(&block)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        @process = IO.popen(streaming_command, "rb", err: File::NULL)
        encoder = build_recording_encoder
        encoder&.start
        read_loop do |data|
          encoder&.push(data)
          block.call(data)
        end
      ensure
        encoder&.stop
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

      def build_recording_encoder
        return unless recording_path

        RecordingEncoder.new(path: recording_path, channels: channels,
                             sample_rate: sample_rate, input_format: "s16le")
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
