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

      def extract_wav(start_time, end_time, tmp_dir:, channel: nil)
        pcm_slice = extract_pcm_slice(start_time, end_time)
        return nil unless pcm_slice

        if channel && channels > 1
          write_wav(demux_channel(pcm_slice, channel), tmp_dir, out_channels: 1)
        else
          write_wav(pcm_slice, tmp_dir)
        end
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

      def demux_channel(pcm_data, channel_index)
        frame_size = channels * BYTES_PER_SAMPLE
        offset = channel_index * BYTES_PER_SAMPLE
        mono = String.new(encoding: Encoding::BINARY)
        pos = 0
        while pos + frame_size <= pcm_data.bytesize
          mono << pcm_data.byteslice(pos + offset, BYTES_PER_SAMPLE)
          pos += frame_size
        end
        mono
      end

      def write_wav(pcm_data, tmp_dir, out_channels: channels)
        path = File.join(tmp_dir, "speaker_#{Time.now.to_f}.wav")
        File.binwrite(path, wav_header(pcm_data.bytesize, out_channels) + pcm_data)
        path
      end

      def wav_header(data_size, num_channels)
        block_align = num_channels * BYTES_PER_SAMPLE
        byte_rate = sample_rate * block_align

        [
          "RIFF", 36 + data_size, "WAVE",
          "fmt ", 16, 1, num_channels, sample_rate, byte_rate, block_align, 16,
          "data", data_size
        ].pack("A4VA4A4VvvVVvvA4V")
      end
    end
  end
end
