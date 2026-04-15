# frozen_string_literal: true

module EarlScribe
  module Audio
    # Captures system audio (via AudioTee) and mic (via sox) in parallel, then
    # either mixes the two mono streams into one (channels=1) or interleaves
    # them into stereo L=system/R=mic (channels=2).
    class DualCapture
      BYTES_PER_SAMPLE = 2
      CHUNK_FRAMES = 960 # 20ms @ 48kHz
      VALID_CHANNELS = [1, 2].freeze

      attr_reader :channels, :sample_rate, :recording_path, :mic_device

      def initialize(mic_device: "default", channels: 1, sample_rate: 48_000, recording_path: nil)
        raise ArgumentError, "channels must be 1 or 2, got #{channels}" unless VALID_CHANNELS.include?(channels)

        @mic_device = mic_device
        @channels = channels
        @sample_rate = sample_rate
        @recording_path = recording_path
        @system = nil
        @mic = nil
      end

      def system_command
        [Config.audiotee_path, "--sample-rate", sample_rate.to_s]
      end

      def mic_command
        ["sox", "-t", "coreaudio", mic_device, "-r", sample_rate.to_s,
         "-c", "1", "-b", "16", "-e", "signed-integer", "-t", "raw", "-"]
      end

      def start_streaming(&block)
        @system = SubprocessStream.spawn(system_command)
        @mic = SubprocessStream.spawn(mic_command)
        encoder = build_recording_encoder
        encoder&.start
        bytes_read, failed = pump(encoder, &block)
        check_health(bytes_read, failed) if failed
      ensure
        encoder&.stop
        stop
      end

      def stop
        @system&.stop
        @mic&.stop
        @system = nil
        @mic = nil
      end

      private

      def pump(encoder, &block)
        chunk_bytes = CHUNK_FRAMES * BYTES_PER_SAMPLE
        bytes = 0
        loop do
          sys = read_exact(@system, chunk_bytes) or return [bytes, :system]
          mic = read_exact(@mic, chunk_bytes) or return [bytes, :mic]
          chunk = combine(sys, mic)
          bytes += chunk.bytesize
          encoder&.push(chunk)
          block.call(chunk)
        end
      end

      def read_exact(stream, bytes)
        buf = +"".b
        while buf.bytesize < bytes
          data = stream.read(bytes - buf.bytesize)
          return nil if data.nil? || data.empty?

          buf << data
        end
        buf
      end

      def check_health(bytes_read, failed)
        stream = failed == :system ? @system : @mic
        raise EarlScribe::Error, "#{stream.name} produced no audio. stderr: #{stream.stderr_tail}" if bytes_read.zero?

        EarlScribe.logger.warn("#{stream.name} ended mid-session: #{stream.stderr_tail}")
      end

      def combine(sys_bytes, mic_bytes)
        @channels == 1 ? mix_mono(sys_bytes, mic_bytes) : interleave_stereo(sys_bytes, mic_bytes)
      end

      def mix_mono(sys_bytes, mic_bytes)
        sys = sys_bytes.unpack("s<*")
        mic = mic_bytes.unpack("s<*")
        sys.zip(mic).map { |s, m| (s.to_i + m.to_i).clamp(-32_768, 32_767) }.pack("s<*")
      end

      def interleave_stereo(sys_bytes, mic_bytes)
        sys = sys_bytes.unpack("s<*")
        mic = mic_bytes.unpack("s<*")
        sys.zip(mic).flatten.pack("s<*")
      end

      def build_recording_encoder
        return unless recording_path

        RecordingEncoder.new(path: recording_path, channels: channels,
                             sample_rate: sample_rate, input_format: "s16le")
      end
    end
  end
end
