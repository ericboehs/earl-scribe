# frozen_string_literal: true

module EarlScribe
  module Audio
    # Captures system audio (via AudioTee) and mic (via sox) in parallel, then
    # either mixes the two mono streams into one (channels=1) or interleaves
    # them into stereo L=system/R=mic (channels=2).
    class DualCapture
      BYTES_PER_SAMPLE = 2
      CHUNK_FRAMES = 960 # 20ms @ 48kHz

      attr_reader :channels, :sample_rate, :recording_path, :mic_device

      def initialize(mic_device: "default", channels: 1, sample_rate: 48_000, recording_path: nil)
        @mic_device = mic_device
        @channels = channels
        @sample_rate = sample_rate
        @recording_path = recording_path
        @system_io = nil
        @mic_io = nil
      end

      def system_command
        [Config.audiotee_path, "--sample-rate", sample_rate.to_s]
      end

      def mic_command
        ["sox", "-t", "coreaudio", mic_device, "-r", sample_rate.to_s,
         "-c", "1", "-b", "16", "-e", "signed-integer", "-t", "raw", "-"]
      end

      def start_streaming(&block)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        @system_io = IO.popen(system_command, "rb", err: File::NULL)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        @mic_io = IO.popen(mic_command, "rb", err: File::NULL)
        encoder = build_recording_encoder
        encoder&.start
        pump(encoder, &block)
      ensure
        encoder&.stop
        stop
      end

      def stop
        close_io(@system_io)
        close_io(@mic_io)
        @system_io = nil
        @mic_io = nil
      end

      private

      def pump(encoder, &block)
        chunk_bytes = CHUNK_FRAMES * BYTES_PER_SAMPLE
        while (sys = read_exact(@system_io, chunk_bytes)) && (mic = read_exact(@mic_io, chunk_bytes))
          chunk = combine(sys, mic)
          encoder&.push(chunk)
          block.call(chunk)
        end
      end

      def read_exact(io, bytes)
        buf = +"".b
        while buf.bytesize < bytes
          data = io.read(bytes - buf.bytesize)
          return nil if data.nil? || data.empty?

          buf << data
        end
        buf
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

      def close_io(io)
        return unless io

        Process.kill("TERM", io.pid)
        io.close
      rescue Errno::ESRCH, Errno::EPERM, IOError
        nil
      end
    end
  end
end
