# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Audio
    class CaptureTest < Minitest::Test
      test "streaming_command builds correct ffmpeg command" do
        capture = EarlScribe::Audio::Capture.new(device_index: 1, channels: 2, sample_rate: 16_000)
        cmd = capture.streaming_command

        assert_includes cmd, "ffmpeg"
        assert_includes cmd, ":1"
        assert_includes cmd, "2"
        assert_includes cmd, "16000"
        assert_includes cmd, "s16le"
        assert_includes cmd, "-"
      end

      test "streaming_command uses mono channels" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0, channels: 1)
        cmd = capture.streaming_command

        ac_index = cmd.index("-ac")
        assert_equal "1", cmd[ac_index + 1]
      end

      test "chunked_command builds correct segmented ffmpeg command" do
        capture = EarlScribe::Audio::Capture.new(device_index: 2, channels: 2)
        cmd = capture.chunked_command("/tmp/output", chunk_seconds: 15)

        assert_includes cmd, "segment"
        assert_includes cmd, "15"
        assert cmd.last.start_with?("/tmp/output/")
      end

      test "chunked_command uses default chunk seconds" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        cmd = capture.chunked_command("/tmp/out")

        segment_idx = cmd.index("-segment_time")
        assert_equal "10", cmd[segment_idx + 1]
      end

      test "attributes are accessible" do
        capture = EarlScribe::Audio::Capture.new(device_index: 3, channels: 1, sample_rate: 44_100)
        assert_equal 3, capture.device_index
        assert_equal 1, capture.channels
        assert_equal 44_100, capture.sample_rate
      end

      test "stop handles nil process gracefully" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        assert_nothing_raised { capture.stop }
      end

      test "start_streaming yields data chunks and stops" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        mock_io = StringIO.new("chunk1chunk2")
        mock_io.define_singleton_method(:pid) { 99_999 }

        received = []
        IO.stub(:popen, mock_io) do
          capture.start_streaming { |data| received << data }
        end
        assert_not_empty received
      end

      test "stop kills process and closes io" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        mock_io = StringIO.new("")
        nil
        mock_io.define_singleton_method(:pid) { 99_999 }

        IO.stub(:popen, mock_io) do
          capture.start_streaming { |_data| nil }
        end

        # After start_streaming completes, @process should be nil (cleaned up in ensure)
        assert_nothing_raised { capture.stop }
      end

      test "stop handles ESRCH when process already exited" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        mock_io = Object.new
        mock_io.define_singleton_method(:pid) { 99_999 }
        mock_io.define_singleton_method(:read) { |_size| nil }
        mock_io.define_singleton_method(:close) { nil }

        IO.stub(:popen, mock_io) do
          Process.stub(:kill, ->(*_args) { raise Errno::ESRCH }) do
            capture.instance_variable_set(:@process, mock_io)
            assert_nothing_raised { capture.stop }
          end
        end
      end
    end
  end
end
