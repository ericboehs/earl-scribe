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
        sys_bytes = ([100, -200] + ([0] * 958)).pack("s<*")
        mic_bytes = ([50, 10_000] + ([0] * 958)).pack("s<*")
        mixed = run_dual_capture(1, sys_bytes, mic_bytes).unpack("s<*")

        assert_equal 150, mixed[0]
        assert_equal 9_800, mixed[1]
      end

      test "start_streaming clamps mixed values to int16 range" do
        sys_bytes = ([30_000] + ([0] * 959)).pack("s<*")
        mic_bytes = ([10_000] + ([0] * 959)).pack("s<*")
        mixed = run_dual_capture(1, sys_bytes, mic_bytes).unpack("s<*")

        assert_equal 32_767, mixed[0]
      end

      test "start_streaming interleaves stereo L=system R=mic when channels=2" do
        sys_bytes = ([1, 2] + ([0] * 958)).pack("s<*")
        mic_bytes = ([3, 4] + ([0] * 958)).pack("s<*")
        interleaved = run_dual_capture(2, sys_bytes, mic_bytes).unpack("s<*")

        assert_equal [1, 3, 2, 4], interleaved.first(4)
      end

      test "start_streaming raises when no audio flows from system" do
        capture = EarlScribe::Audio::DualCapture.new
        sys = build_stream("", stderr: "sys failure", name: "audiotee")
        mic = build_stream(([0] * 960).pack("s<*"), name: "sox")

        EarlScribe::Audio::SubprocessStream.stub(:spawn, ->(cmd) { cmd.first == "sox" ? mic : sys }) do
          error = assert_raises(EarlScribe::Error) do
            capture.start_streaming { |_data| nil }
          end
          assert_includes error.message, "audiotee"
          assert_includes error.message, "sys failure"
        end
      end

      test "start_streaming warns when a stream dies mid-session but some audio flowed" do
        capture = EarlScribe::Audio::DualCapture.new
        sys = build_stream(([10] * 1920).pack("s<*"), name: "audiotee")
        mic = build_stream(([5] * 1920).pack("s<*"), name: "sox")

        logged = []
        logger = Logger.new(StringIO.new)
        logger.define_singleton_method(:warn) { |msg| logged << msg }

        EarlScribe.stub(:logger, logger) do
          EarlScribe::Audio::SubprocessStream.stub(:spawn, ->(cmd) { cmd.first == "sox" ? mic : sys }) do
            capture.start_streaming { |_data| nil }
          end
        end

        assert_match(/(audiotee|sox).*ended mid-session/, logged.join)
      end

      test "start_streaming tees to recording encoder when recording_path set" do
        capture = EarlScribe::Audio::DualCapture.new(channels: 1, recording_path: "/tmp/r.m4a")
        bytes = ([10] * 960).pack("s<*")
        sys = build_stream(bytes, name: "audiotee")
        mic = build_stream(bytes, name: "sox")
        encoder_io = StringIO.new(+"".b)
        encoder_io.define_singleton_method(:pid) { 99_993 }

        silence_logger do
          EarlScribe::Audio::SubprocessStream.stub(:spawn, ->(cmd) { cmd.first == "sox" ? mic : sys }) do
            IO.stub(:popen, encoder_io) do
              capture.start_streaming { |_data| nil }
            end
          end
        end

        assert_not_empty encoder_io.string
      end

      test "stop is idempotent" do
        capture = EarlScribe::Audio::DualCapture.new
        assert_nothing_raised { capture.stop }
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

      test "initialize raises on invalid channels" do
        assert_raises(ArgumentError) { EarlScribe::Audio::DualCapture.new(channels: 0) }
        assert_raises(ArgumentError) { EarlScribe::Audio::DualCapture.new(channels: 3) }
      end

      private

      def run_dual_capture(channels, sys_bytes, mic_bytes)
        capture = EarlScribe::Audio::DualCapture.new(channels: channels)
        sys = build_stream(sys_bytes, name: "audiotee")
        mic = build_stream(mic_bytes, name: "sox")

        received = []
        silence_logger do
          EarlScribe::Audio::SubprocessStream.stub(:spawn, ->(cmd) { cmd.first == "sox" ? mic : sys }) do
            capture.start_streaming { |data| received << data }
          end
        end
        received.first
      end

      def silence_logger
        original = EarlScribe.logger
        EarlScribe.logger = Logger.new(StringIO.new)
        yield
      ensure
        EarlScribe.logger = original
      end

      def build_stream(data, name:, stderr: "")
        r, w = IO.pipe
        w.write(data.to_s.b) unless data.to_s.empty?
        w.close
        stream = Object.new
        stream.define_singleton_method(:io) { r }
        stream.define_singleton_method(:stop) do
          r.close unless r.closed?
        end
        stream.define_singleton_method(:name) { name }
        stream.define_singleton_method(:stderr_tail) { |**_| stderr }
        stream
      end
    end
  end
end
