# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Audio
    class DualCaptureTest < Minitest::Test
      test "system_command uses configured audiotee path with sample rate" do
        capture = EarlScribe::Audio::DualCapture.new(sample_rate: 48_000)
        EarlScribe::Config.stub(:audiotee_path, "/opt/audiotee") do
          cmd = capture.system_command

          assert_equal "/opt/audiotee", cmd.first
          assert_includes cmd, "--sample-rate"
          assert_includes cmd, "48000"
        end
      end

      test "mic_command uses sox with given device and mono s16le raw output" do
        capture = EarlScribe::Audio::DualCapture.new(mic_device: "Streamer X Main", sample_rate: 48_000)
        cmd = capture.mic_command

        assert_equal "sox", cmd.first
        assert_includes cmd, "Streamer X Main"
        assert_includes cmd, "48000"
        assert_equal "1", cmd[cmd.index("-c") + 1]
        assert_equal "16", cmd[cmd.index("-b") + 1]
        assert_equal "-", cmd.last
      end

      test "start_streaming mixes mono chunks by summing and clamping" do
        capture = EarlScribe::Audio::DualCapture.new(channels: 1)
        sys_samples = [100, -200] + ([0] * 958)
        mic_samples = [50, 10_000] + ([0] * 958)
        sys_io = StringIO.new(sys_samples.pack("s<*"))
        sys_io.define_singleton_method(:pid) { 99_991 }
        mic_io = StringIO.new(mic_samples.pack("s<*"))
        mic_io.define_singleton_method(:pid) { 99_992 }

        received = []
        IO.stub(:popen, ->(cmd, *_args, **_opts) { cmd.first == "sox" ? mic_io : sys_io }) do
          capture.start_streaming { |data| received << data }
        end

        mixed = received.first.unpack("s<*")
        assert_equal 150, mixed[0]
        assert_equal 9_800, mixed[1]
      end

      test "start_streaming clamps mixed values to int16 range" do
        capture = EarlScribe::Audio::DualCapture.new(channels: 1)
        sys_samples = [30_000] + ([0] * 959)
        mic_samples = [10_000] + ([0] * 959)
        sys_io = StringIO.new(sys_samples.pack("s<*"))
        sys_io.define_singleton_method(:pid) { 99_991 }
        mic_io = StringIO.new(mic_samples.pack("s<*"))
        mic_io.define_singleton_method(:pid) { 99_992 }

        received = []
        IO.stub(:popen, ->(cmd, *_args, **_opts) { cmd.first == "sox" ? mic_io : sys_io }) do
          capture.start_streaming { |data| received << data }
        end

        mixed = received.first.unpack("s<*")
        assert_equal 32_767, mixed[0]
      end

      test "start_streaming interleaves stereo L=system R=mic when channels=2" do
        capture = EarlScribe::Audio::DualCapture.new(channels: 2)
        sys_samples = [1, 2] + ([0] * 958)
        mic_samples = [3, 4] + ([0] * 958)
        sys_io = StringIO.new(sys_samples.pack("s<*"))
        sys_io.define_singleton_method(:pid) { 99_991 }
        mic_io = StringIO.new(mic_samples.pack("s<*"))
        mic_io.define_singleton_method(:pid) { 99_992 }

        received = []
        IO.stub(:popen, ->(cmd, *_args, **_opts) { cmd.first == "sox" ? mic_io : sys_io }) do
          capture.start_streaming { |data| received << data }
        end

        interleaved = received.first.unpack("s<*")
        assert_equal [1, 3, 2, 4], interleaved.first(4)
      end

      test "start_streaming tees to recording encoder when recording_path set" do
        capture = EarlScribe::Audio::DualCapture.new(channels: 1, recording_path: "/tmp/r.m4a")
        bytes = ([10] * 960).pack("s<*")
        sys_io = StringIO.new(bytes)
        sys_io.define_singleton_method(:pid) { 99_991 }
        mic_io = StringIO.new(bytes)
        mic_io.define_singleton_method(:pid) { 99_992 }
        encoder_io = StringIO.new(+"".b)
        encoder_io.define_singleton_method(:pid) { 99_993 }

        popen = lambda { |cmd, *_args, **_opts|
          if cmd.include?("pipe:0")
            encoder_io
          elsif cmd.first == "sox"
            mic_io
          else
            sys_io
          end
        }

        IO.stub(:popen, popen) do
          capture.start_streaming { |_data| nil }
        end

        assert_not_empty encoder_io.string
      end

      test "stop handles ESRCH gracefully" do
        capture = EarlScribe::Audio::DualCapture.new
        mock_io = Object.new
        mock_io.define_singleton_method(:pid) { 99_999 }
        mock_io.define_singleton_method(:close) { nil }

        capture.instance_variable_set(:@system_io, mock_io)
        capture.instance_variable_set(:@mic_io, mock_io)
        Process.stub(:kill, ->(*_args) { raise Errno::ESRCH }) do
          assert_nothing_raised { capture.stop }
        end
      end

      test "stop is a no-op when processes nil" do
        capture = EarlScribe::Audio::DualCapture.new
        assert_nothing_raised { capture.stop }
      end

      test "attributes are accessible" do
        capture = EarlScribe::Audio::DualCapture.new(mic_device: "MyMic", channels: 2,
                                                     sample_rate: 16_000, recording_path: "/tmp/r.m4a")
        assert_equal "MyMic", capture.mic_device
        assert_equal 2, capture.channels
        assert_equal 16_000, capture.sample_rate
        assert_equal "/tmp/r.m4a", capture.recording_path
      end
    end
  end
end
