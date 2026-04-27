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

      attr_reader :channels, :sample_rate, :recording_path, :mic_device, :mic_gain_db

      def initialize(mic_device: "default", channels: 1, sample_rate: 48_000, recording_path: nil,
                     mic_gain_db: nil)
        raise ArgumentError, "channels must be 1 or 2, got #{channels}" unless VALID_CHANNELS.include?(channels)

        @mic_device = mic_device
        @channels = channels
        @sample_rate = sample_rate
        @recording_path = recording_path
        @mic_gain_db = mic_gain_db || Config.mic_gain_db
        @system = nil
        @mic = nil
      end

      def system_command
        [Config.audiotee_path, "--sample-rate", sample_rate.to_s]
      end

      def mic_command
        cmd = ["sox", "-t", "coreaudio", mic_device, "-r", sample_rate.to_s,
               "-c", "1", "-b", "16", "-e", "signed-integer", "-t", "raw", "-"]
        cmd += ["gain", mic_gain_db.to_s] if mic_gain_db && mic_gain_db != 0
        cmd
      end

      def start_streaming(&block)
        @system = SubprocessStream.spawn(system_command)
        @mic = SubprocessStream.spawn(mic_command)
        encoder = build_recording_encoder
        encoder&.start
        bytes_read, failed = pump(encoder, &block)
        check_health(bytes_read, failed)
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
        buffers = { system: +"".b, mic: +"".b }
        bytes = 0
        loop do
          ended = drain_ready_into(buffers)
          return [bytes, ended] if ended

          bytes += emit_aligned_chunks(buffers, chunk_bytes, encoder, &block)
        end
      end

      def drain_ready_into(buffers)
        ready, = IO.select([@system.io, @mic.io])
        ready.each do |io|
          key = io == @system.io ? :system : :mic
          buffers[key] << io.readpartial(16_384)
        rescue EOFError
          return key
        end
        nil
      end

      def emit_aligned_chunks(buffers, chunk_bytes, encoder, &block)
        emitted = 0
        while buffers[:system].bytesize >= chunk_bytes && buffers[:mic].bytesize >= chunk_bytes
          chunk = combine(buffers[:system].slice!(0, chunk_bytes), buffers[:mic].slice!(0, chunk_bytes))
          emitted += chunk.bytesize
          encoder&.push(chunk)
          block.call(chunk)
        end
        emitted
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
