# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Audio
    class PcmBufferTest < Minitest::Test
      setup do
        @buffer = PcmBuffer.new(sample_rate: 16_000, channels: 1)
      end

      test "append stores data and duration reflects it" do
        one_second = "\x00" * 32_000 # 16000 samples * 1 channel * 2 bytes
        @buffer.append(one_second)

        assert_in_delta 1.0, @buffer.duration, 0.01
      end

      test "append accumulates data across calls" do
        half_second = "\x00" * 16_000
        @buffer.append(half_second)
        @buffer.append(half_second)

        assert_in_delta 1.0, @buffer.duration, 0.01
      end

      test "append trims old data beyond max_duration" do
        buffer = PcmBuffer.new(sample_rate: 16_000, channels: 1, max_duration: 2)
        one_second = "\x00" * 32_000

        3.times { buffer.append(one_second) }

        assert_in_delta 2.0, buffer.duration, 0.01
      end

      test "extract_wav returns valid WAV file for time range" do
        Dir.mktmpdir("pcm_test") do |tmp_dir|
          pcm_data = "\x01" * 64_000 # 2 seconds of mono 16kHz
          @buffer.append(pcm_data)

          path = @buffer.extract_wav(0.0, 1.0, tmp_dir: tmp_dir)
          assert path
          assert File.exist?(path)

          wav_data = File.binread(path)
          assert_equal "RIFF", wav_data[0, 4]
          assert_equal "WAVE", wav_data[8, 4]
          assert_equal "fmt ", wav_data[12, 4]
          assert_equal "data", wav_data[36, 4]
        end
      end

      test "extract_wav returns nil when range has been trimmed" do
        buffer = PcmBuffer.new(sample_rate: 16_000, channels: 1, max_duration: 2)
        one_second = "\x00" * 32_000

        4.times { buffer.append(one_second) }

        Dir.mktmpdir("pcm_test") do |tmp_dir|
          result = buffer.extract_wav(0.0, 0.5, tmp_dir: tmp_dir)
          assert_nil result
        end
      end

      test "extract_wav clamps to available range" do
        Dir.mktmpdir("pcm_test") do |tmp_dir|
          pcm_data = "\x01" * 64_000 # 2 seconds
          @buffer.append(pcm_data)

          path = @buffer.extract_wav(0.0, 5.0, tmp_dir: tmp_dir)
          assert path

          wav_data = File.binread(path)
          data_size = wav_data[40, 4].unpack1("V")
          assert_equal 64_000, data_size
        end
      end

      test "WAV header has correct sample rate channels and data size" do
        Dir.mktmpdir("pcm_test") do |tmp_dir|
          buffer = PcmBuffer.new(sample_rate: 16_000, channels: 2)
          pcm_data = "\x01" * 128_000 # 2 seconds of stereo 16kHz
          buffer.append(pcm_data)

          path = buffer.extract_wav(0.0, 1.0, tmp_dir: tmp_dir)
          wav_data = File.binread(path)

          channels = wav_data[22, 2].unpack1("v")
          sample_rate = wav_data[24, 4].unpack1("V")
          bits_per_sample = wav_data[34, 2].unpack1("v")
          data_size = wav_data[40, 4].unpack1("V")

          assert_equal 2, channels
          assert_equal 16_000, sample_rate
          assert_equal 16, bits_per_sample
          assert_equal 64_000, data_size # 1 second * 16000 * 2 channels * 2 bytes
        end
      end

      test "extract_wav with channel extracts mono from stereo" do
        Dir.mktmpdir("pcm_test") do |tmp_dir|
          buffer = PcmBuffer.new(sample_rate: 16_000, channels: 2)
          # 1 second stereo: interleaved L/R samples (each 2 bytes)
          # L=0x0100 R=0x0200 repeated for 16000 frames
          frame = [0x0001, 0x0002].pack("v2")
          pcm_data = frame * 16_000
          buffer.append(pcm_data)

          path = buffer.extract_wav(0.0, 1.0, tmp_dir: tmp_dir, channel: 0)
          wav_data = File.binread(path)

          # Header should say mono
          assert_equal 1, wav_data[22, 2].unpack1("v")
          # Data size should be half (mono)
          data_size = wav_data[40, 4].unpack1("V")
          assert_equal 32_000, data_size # 16000 samples * 2 bytes

          # All samples should be left channel value (0x0001)
          pcm = wav_data[44..]
          samples = pcm.unpack("v*")
          assert(samples.all? { |s| s == 0x0001 })
        end
      end

      test "extract_wav with channel 1 extracts right channel" do
        Dir.mktmpdir("pcm_test") do |tmp_dir|
          buffer = PcmBuffer.new(sample_rate: 16_000, channels: 2)
          frame = [0x0001, 0x0002].pack("v2")
          pcm_data = frame * 16_000
          buffer.append(pcm_data)

          path = buffer.extract_wav(0.0, 1.0, tmp_dir: tmp_dir, channel: 1)
          wav_data = File.binread(path)

          pcm = wav_data[44..]
          samples = pcm.unpack("v*")
          assert(samples.all? { |s| s == 0x0002 })
        end
      end

      test "extract_wav without channel keeps stereo" do
        Dir.mktmpdir("pcm_test") do |tmp_dir|
          buffer = PcmBuffer.new(sample_rate: 16_000, channels: 2)
          pcm_data = "\x01" * 128_000 # 2 seconds stereo
          buffer.append(pcm_data)

          path = buffer.extract_wav(0.0, 1.0, tmp_dir: tmp_dir)
          wav_data = File.binread(path)

          assert_equal 2, wav_data[22, 2].unpack1("v")
        end
      end

      test "duration returns zero for empty buffer" do
        assert_in_delta 0.0, @buffer.duration, 0.001
      end

      test "extract_wav returns nil for empty buffer" do
        Dir.mktmpdir("pcm_test") do |tmp_dir|
          assert_nil @buffer.extract_wav(0.0, 1.0, tmp_dir: tmp_dir)
        end
      end
    end
  end
end
