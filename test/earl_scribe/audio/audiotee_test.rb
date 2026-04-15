# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Audio
    class AudioTeeTest < Minitest::Test
      test "streaming_command uses configured audiotee path with sample rate" do
        capture = EarlScribe::Audio::AudioTee.new(sample_rate: 48_000)
        EarlScribe::Config.stub(:audiotee_path, "/opt/audiotee") do
          cmd = capture.streaming_command

          assert_equal "/opt/audiotee", cmd.first
          assert_includes cmd, "--sample-rate"
          assert_includes cmd, "48000"
        end
      end

      test "streaming_command omits stereo flag for mono" do
        capture = EarlScribe::Audio::AudioTee.new(channels: 1)
        assert_not_includes capture.streaming_command, "--stereo"
      end

      test "streaming_command includes stereo flag when channels > 1" do
        capture = EarlScribe::Audio::AudioTee.new(channels: 2)
        assert_includes capture.streaming_command, "--stereo"
      end

      test "attributes are accessible" do
        capture = EarlScribe::Audio::AudioTee.new(channels: 2, sample_rate: 16_000,
                                                  recording_path: "/tmp/r.m4a")
        assert_equal 2, capture.channels
        assert_equal 16_000, capture.sample_rate
        assert_equal "/tmp/r.m4a", capture.recording_path
      end

      test "start_streaming yields s16le chunks directly without conversion" do
        capture = EarlScribe::Audio::AudioTee.new
        s16_data = [100, -200].pack("s<*")
        stream = build_stream(s16_data)

        received = []
        EarlScribe::Audio::SubprocessStream.stub(:spawn, stream) do
          capture.start_streaming { |data| received << data }
        end

        assert_equal s16_data, received.first
      end

      test "start_streaming tees data to recording encoder when recording_path set" do
        capture = EarlScribe::Audio::AudioTee.new(recording_path: "/tmp/out.m4a")
        s16_data = [100, 200].pack("s<*")
        stream = build_stream(s16_data)
        encoder_data = StringIO.new(+"".b)
        encoder_data.define_singleton_method(:pid) { 99_998 }

        EarlScribe::Audio::SubprocessStream.stub(:spawn, stream) do
          IO.stub(:popen, encoder_data) do
            capture.start_streaming { |_data| nil }
          end
        end

        assert_equal s16_data, encoder_data.string
      end

      test "start_streaming raises when no audio flows" do
        capture = EarlScribe::Audio::AudioTee.new
        stream = build_stream("", stderr: "permission denied")

        EarlScribe::Audio::SubprocessStream.stub(:spawn, stream) do
          error = assert_raises(EarlScribe::Error) do
            capture.start_streaming { |_data| nil }
          end
          assert_includes error.message, "produced no audio"
          assert_includes error.message, "permission denied"
        end
      end

      test "stop is idempotent" do
        capture = EarlScribe::Audio::AudioTee.new
        assert_nothing_raised { capture.stop }
        assert_nothing_raised { capture.stop }
      end

      test "initialize raises on invalid channels" do
        assert_raises(ArgumentError) { EarlScribe::Audio::AudioTee.new(channels: 0) }
        assert_raises(ArgumentError) { EarlScribe::Audio::AudioTee.new(channels: 3) }
      end

      private

      def build_stream(data, stderr: "")
        io = StringIO.new(data.b)
        stream = Object.new
        stream.define_singleton_method(:read) { |n| io.read(n) }
        stream.define_singleton_method(:stop) { nil }
        stream.define_singleton_method(:name) { "audiotee" }
        stream.define_singleton_method(:stderr_tail) { |**_| stderr }
        stream
      end
    end
  end
end
