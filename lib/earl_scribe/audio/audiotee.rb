# frozen_string_literal: true

module EarlScribe
  module Audio
    # Captures system audio via the audiotee CLI (Core Audio Taps API, macOS 14.2+).
    # Quacks like Audio::Capture but bypasses device selection entirely.
    class AudioTee
      VALID_CHANNELS = [1, 2].freeze

      attr_reader :channels, :sample_rate, :recording_path

      def initialize(channels: 1, sample_rate: 48_000, recording_path: nil)
        raise ArgumentError, "channels must be 1 or 2, got #{channels}" unless VALID_CHANNELS.include?(channels)

        @channels = channels
        @sample_rate = sample_rate
        @recording_path = recording_path
        @stream = nil
      end

      def streaming_command
        cmd = [Config.audiotee_path, "--sample-rate", sample_rate.to_s]
        cmd << "--stereo" if channels > 1
        cmd
      end

      def start_streaming(&block)
        @stream = SubprocessStream.spawn(streaming_command)
        encoder = build_recording_encoder
        encoder&.start
        bytes_read = pump_audio(encoder, &block)
        check_health(bytes_read)
      ensure
        encoder&.stop
        stop
      end

      def stop
        @stream&.stop
        @stream = nil
      end

      private

      def pump_audio(encoder, &block)
        bytes = 0
        chunk_size = 16_384
        while (data = @stream.read(chunk_size))
          bytes += data.bytesize
          encoder&.push(data)
          block.call(data)
        end
        bytes
      end

      def check_health(bytes_read)
        return if bytes_read.positive?

        raise EarlScribe::Error,
              "audiotee produced no audio. Check System Settings → Privacy & Security → " \
              "System Audio Recording. stderr: #{@stream.stderr_tail}"
      end

      def build_recording_encoder
        return unless recording_path

        RecordingEncoder.new(path: recording_path, channels: channels,
                             sample_rate: sample_rate, input_format: "s16le")
      end
    end
  end
end
