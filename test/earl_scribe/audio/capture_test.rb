# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Audio
    class CaptureTest < Minitest::Test
      test "streaming_command uses sox when available and device_name set" do
        capture = EarlScribe::Audio::Capture.new(device_index: 1, device_name: "Loopback Meeting",
                                                 channels: 1, sample_rate: 48_000)
        capture.stub(:sox_available?, true) do
          cmd = capture.streaming_command

          assert_includes cmd, "sox"
          assert_includes cmd, "coreaudio"
          assert_includes cmd, "Loopback Meeting"
          assert_includes cmd, "48000"
        end
      end

      test "streaming_command falls back to ffmpeg when sox unavailable" do
        capture = EarlScribe::Audio::Capture.new(device_index: 1, device_name: "Loopback Meeting",
                                                 channels: 2, sample_rate: 48_000)
        capture.stub(:sox_available?, false) do
          cmd = capture.streaming_command

          assert_includes cmd, "ffmpeg"
          assert_includes cmd, ":1"
          assert_includes cmd, "f32le"
        end
      end

      test "streaming_command falls back to ffmpeg when no device_name" do
        capture = EarlScribe::Audio::Capture.new(device_index: 1, channels: 2, sample_rate: 48_000)
        cmd = capture.streaming_command

        assert_includes cmd, "ffmpeg"
        assert_includes cmd, "48000"
        assert_includes cmd, "f32le"
      end

      test "streaming_command uses mono channels" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0, channels: 1)
        capture.stub(:sox_available?, false) do
          cmd = capture.streaming_command

          ac_index = cmd.index("-ac")
          assert_equal "1", cmd[ac_index + 1]
        end
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

      test "streaming_command never includes recording args" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0, recording_path: "/tmp/test.m4a")
        cmd = capture.streaming_command

        assert_not_includes cmd, "aac"
        assert_equal "-", cmd.last
      end

      test "start_streaming tees data to encoder when recording_path set" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0, recording_path: "/tmp/test.m4a")
        f32_data = [0.5, -0.5].pack("e*")
        mock_io = StringIO.new(f32_data)
        mock_io.define_singleton_method(:pid) { 99_999 }

        encoder_data = StringIO.new
        encoder_data.define_singleton_method(:pid) { 99_998 }

        received = []
        IO.stub(:popen, ->(cmd, *args, **_opts) { cmd.include?("pipe:0") ? encoder_data : mock_io }) do
          capture.start_streaming { |data| received << data }
        end

        assert_not_empty received
        assert_not_empty encoder_data.string
        # Block receives s16le converted data
        assert_equal [0.5, -0.5].map { |f| (f * 32_767).to_i }.pack("s<*"), received.first
      end

      test "start_streaming skips encoder when no recording_path" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        f32_data = [0.5].pack("e*")
        mock_io = StringIO.new(f32_data)
        mock_io.define_singleton_method(:pid) { 99_999 }

        popen_calls = []
        popen_stub = lambda { |cmd, *_args, **_opts|
          popen_calls << cmd
          mock_io
        }
        IO.stub(:popen, popen_stub) do
          capture.start_streaming { |_data| nil }
        end

        assert_equal 1, popen_calls.size
      end

      test "sox_available? checks for sox binary" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        capture.remove_instance_variable(:@sox_available) if capture.instance_variable_defined?(:@sox_available)
        result = capture.sox_available?
        assert_includes [true, false], result
      end

      test "chunked_command includes AAC args when recording_path set" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0, recording_path: "/tmp/test.m4a")
        cmd = capture.chunked_command("/tmp/output")

        assert_includes cmd, "aac"
        assert_includes cmd, "64k"
        assert_equal "/tmp/test.m4a", cmd.last
      end

      test "recording_path is accessible" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0, recording_path: "/tmp/rec.m4a")
        assert_equal "/tmp/rec.m4a", capture.recording_path
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
        mock_io = StringIO.new([0.1, 0.2, 0.3].pack("e*"))
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

      test "start_chunked delegates to ChunkPoller" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        mock_io = build_mock_chunked_io
        poll_called = false
        final_called = false
        mock_poller = build_mock_poller(
          on_poll: -> { poll_called = true },
          on_final: -> { final_called = true }
        )

        EarlScribe::Audio::ChunkPoller.stub(:new, mock_poller) do
          IO.stub(:popen, mock_io) do
            Process.stub(:kill, ->(*_args) {}) do
              capture.start_chunked("/tmp/ignored") { |_path| nil }
            end
          end
        end

        assert poll_called, "Expected ChunkPoller#poll to be called"
        assert final_called, "Expected yield_final_chunk to be called"
      end

      test "start_chunked stops ffmpeg on completion" do
        capture = EarlScribe::Audio::Capture.new(device_index: 0)
        mock_io = build_mock_chunked_io
        mock_poller = build_mock_poller

        killed = false
        EarlScribe::Audio::ChunkPoller.stub(:new, mock_poller) do
          IO.stub(:popen, mock_io) do
            Process.stub(:kill, ->(*_args) { killed = true }) do
              capture.start_chunked("/tmp/ignored") { |_path| nil }
            end
          end
        end

        assert killed, "Expected ffmpeg process to be killed"
      end

      private

      def build_mock_chunked_io
        io = Object.new
        io.define_singleton_method(:pid) { 99_999 }
        io.define_singleton_method(:close) { nil }
        io
      end

      def build_mock_poller(on_poll: -> {}, on_final: -> {})
        poller = Object.new
        poller.define_singleton_method(:poll) { |&_block| on_poll.call }
        poller.define_singleton_method(:yield_final_chunk) { |&_block| on_final.call }
        poller
      end
    end
  end
end
