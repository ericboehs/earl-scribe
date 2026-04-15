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
        mock_io = StringIO.new(s16_data)
        mock_io.define_singleton_method(:pid) { 99_999 }

        received = []
        IO.stub(:popen, mock_io) do
          capture.start_streaming { |data| received << data }
        end

        assert_equal s16_data, received.first
      end

      test "start_streaming tees data to recording encoder when recording_path set" do
        capture = EarlScribe::Audio::AudioTee.new(recording_path: "/tmp/out.m4a")
        s16_data = [100, 200].pack("s<*")
        mock_io = StringIO.new(s16_data)
        mock_io.define_singleton_method(:pid) { 99_999 }

        encoder_data = StringIO.new(+"".b)
        encoder_data.define_singleton_method(:pid) { 99_998 }

        received = []
        IO.stub(:popen, ->(cmd, *_args, **_opts) { cmd.include?("pipe:0") ? encoder_data : mock_io }) do
          capture.start_streaming { |data| received << data }
        end

        assert_equal s16_data, encoder_data.string
        assert_equal s16_data, received.first
      end

      test "stop kills process and handles ESRCH gracefully" do
        capture = EarlScribe::Audio::AudioTee.new
        mock_io = Object.new
        mock_io.define_singleton_method(:pid) { 99_999 }
        mock_io.define_singleton_method(:close) { nil }

        capture.instance_variable_set(:@process, mock_io)
        Process.stub(:kill, ->(*_args) { raise Errno::ESRCH }) do
          assert_nothing_raised { capture.stop }
        end
      end

      test "stop is a no-op when process nil" do
        capture = EarlScribe::Audio::AudioTee.new
        assert_nothing_raised { capture.stop }
      end

      test "initialize raises on invalid channels" do
        assert_raises(ArgumentError) { EarlScribe::Audio::AudioTee.new(channels: 0) }
        assert_raises(ArgumentError) { EarlScribe::Audio::AudioTee.new(channels: 3) }
      end
    end
  end
end
