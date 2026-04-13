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

      test "start_chunked yields completed wav paths via final chunk" do
        Dir.mktmpdir("capture_test") do |tmp_dir|
          capture = EarlScribe::Audio::Capture.new(device_index: 0)

          wav1 = File.join(tmp_dir, "20260302_100000.wav")
          wav2 = File.join(tmp_dir, "20260302_100010.wav")
          File.write(wav1, "fake audio 1")
          File.write(wav2, "fake audio 2")

          mock_io = Object.new
          mock_io.define_singleton_method(:pid) { 99_999 }
          mock_io.define_singleton_method(:close) { nil }

          yielded = []

          # Return immediately so ensure block yields final chunks
          capture.define_singleton_method(:poll_for_chunks) { |_dir| nil }

          IO.stub(:popen, mock_io) do
            Process.stub(:kill, ->(*_args) {}) do
              capture.start_chunked(tmp_dir) { |path| yielded << path }
            end
          end

          assert_includes yielded, wav1
          assert_includes yielded, wav2
        end
      end

      test "start_chunked stops ffmpeg on completion" do
        Dir.mktmpdir("capture_test") do |tmp_dir|
          capture = EarlScribe::Audio::Capture.new(device_index: 0)

          mock_io = Object.new
          mock_io.define_singleton_method(:pid) { 99_999 }
          mock_io.define_singleton_method(:close) { nil }

          killed = false
          kill_proc = lambda { |*_args|
            killed = true
          }

          capture.define_singleton_method(:poll_for_chunks) { |_dir| nil }

          IO.stub(:popen, mock_io) do
            Process.stub(:kill, kill_proc) do
              capture.start_chunked(tmp_dir) { |_path| nil }
            end
          end

          assert killed, "Expected ffmpeg process to be killed"
        end
      end

      test "start_chunked skips already-yielded files in final yield" do
        Dir.mktmpdir("capture_test") do |tmp_dir|
          capture = EarlScribe::Audio::Capture.new(device_index: 0)

          wav1 = File.join(tmp_dir, "20260302_100000.wav")
          File.write(wav1, "audio data")

          mock_io = Object.new
          mock_io.define_singleton_method(:pid) { 99_999 }
          mock_io.define_singleton_method(:close) { nil }

          # Pre-mark wav1 as already yielded during poll_for_chunks
          capture.define_singleton_method(:poll_for_chunks) do |_dir|
            @yielded = Set.new([wav1])
          end

          yielded = []
          IO.stub(:popen, mock_io) do
            Process.stub(:kill, ->(*_args) {}) do
              capture.start_chunked(tmp_dir) { |path| yielded << path }
            end
          end

          assert_empty yielded
        end
      end

      test "start_chunked skips zero-byte files in final yield" do
        Dir.mktmpdir("capture_test") do |tmp_dir|
          capture = EarlScribe::Audio::Capture.new(device_index: 0)

          empty_wav = File.join(tmp_dir, "20260302_100000.wav")
          File.write(empty_wav, "")

          mock_io = Object.new
          mock_io.define_singleton_method(:pid) { 99_999 }
          mock_io.define_singleton_method(:close) { nil }

          capture.define_singleton_method(:poll_for_chunks) { |_dir| nil }

          yielded = []
          IO.stub(:popen, mock_io) do
            Process.stub(:kill, ->(*_args) {}) do
              capture.start_chunked(tmp_dir) { |path| yielded << path }
            end
          end

          assert_empty yielded
        end
      end

      test "poll_for_chunks skips zero-byte files in completed chunks" do
        Dir.mktmpdir("capture_test") do |tmp_dir|
          capture = EarlScribe::Audio::Capture.new(device_index: 0)
          capture.instance_variable_set(:@yielded, Set.new)

          wav1 = File.join(tmp_dir, "20260302_100000.wav")
          wav2 = File.join(tmp_dir, "20260302_100010.wav")
          wav3 = File.join(tmp_dir, "20260302_100020.wav")
          File.write(wav1, "")          # zero-byte, should skip
          File.write(wav2, "audio")     # has content, should yield
          File.write(wav3, "in progress")

          yielded = []
          capture.define_singleton_method(:sleep) { |_s| raise StopIteration }

          begin
            capture.send(:poll_for_chunks, tmp_dir) { |path| yielded << path }
          rescue StopIteration
            nil
          end

          assert_equal [wav2], yielded
        end
      end

      test "poll_for_chunks yields previous file when new one appears" do
        Dir.mktmpdir("capture_test") do |tmp_dir|
          capture = EarlScribe::Audio::Capture.new(device_index: 0)
          capture.instance_variable_set(:@yielded, Set.new)

          wav1 = File.join(tmp_dir, "20260302_100000.wav")
          wav2 = File.join(tmp_dir, "20260302_100010.wav")
          File.write(wav1, "audio 1")
          File.write(wav2, "audio 2")

          yielded = []
          call_count = 0

          # Run two iterations so the duplicate-skip branch is exercised
          capture.define_singleton_method(:sleep) do |_s|
            call_count += 1
            raise StopIteration if call_count >= 2
          end

          begin
            capture.send(:poll_for_chunks, tmp_dir) { |path| yielded << path }
          rescue StopIteration
            nil
          end

          # wav1 yielded once (second iteration skips it as duplicate)
          assert_equal [wav1], yielded
        end
      end
    end
  end
end
