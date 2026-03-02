# frozen_string_literal: true

require "monitor"

module EarlScribe
  module Audio
    # Thread-safe rolling buffer for raw PCM audio with WAV extraction
    class PcmBuffer
      include MonitorMixin

      BYTES_PER_SAMPLE = 2 # s16le

      attr_reader :sample_rate, :channels

      def initialize(sample_rate:, channels:, max_duration: 30)
        super()
        @sample_rate = sample_rate
        @channels = channels
        @max_bytes = max_duration * bytes_per_second
        @buffer = String.new(encoding: Encoding::BINARY)
        @start_offset = 0.0
      end

      def append(data)
        synchronize do
          @buffer << data
          trim_buffer
        end
      end

      def duration
        synchronize { @buffer.bytesize.to_f / bytes_per_second }
      end

      def extract_wav(start_time, end_time, tmp_dir:)
        pcm_slice = extract_pcm_slice(start_time, end_time)
        return nil unless pcm_slice

        write_wav(pcm_slice, tmp_dir)
      end

      private

      def bytes_per_second
        sample_rate * channels * BYTES_PER_SAMPLE
      end

      def trim_buffer
        excess = @buffer.bytesize - @max_bytes
        return unless excess.positive?

        @buffer.slice!(0, excess)
        @start_offset += excess.to_f / bytes_per_second
      end

      def extract_pcm_slice(start_time, end_time)
        synchronize do
          relative_start = start_time - @start_offset
          relative_end = end_time - @start_offset

          return nil if relative_start.negative? && relative_end.negative?

          byte_start = [(relative_start * bytes_per_second).to_i, 0].max
          byte_end = [(relative_end * bytes_per_second).to_i, @buffer.bytesize].min

          return nil if byte_start >= byte_end

          @buffer.byteslice(byte_start, byte_end - byte_start)
        end
      end

      def write_wav(pcm_data, tmp_dir)
        path = File.join(tmp_dir, "speaker_#{Time.now.to_f}.wav")
        File.binwrite(path, wav_header(pcm_data.bytesize) + pcm_data)
        path
      end

      def wav_header(data_size)
        block_align = channels * BYTES_PER_SAMPLE

        [
          "RIFF", 36 + data_size, "WAVE",
          "fmt ", 16, 1, channels, sample_rate, bytes_per_second, block_align, 16,
          "data", data_size
        ].pack("A4VA4A4VvvVVvvA4V")
      end
    end
  end
end
