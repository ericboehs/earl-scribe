# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Audio
    class RecordingEncoderTest < Minitest::Test
      test "start spawns ffmpeg subprocess and push enqueues data" do
        encoder_io = StringIO.new
        encoder_io.define_singleton_method(:pid) { 99_999 }

        rec = RecordingEncoder.new(path: "/tmp/rec.m4a", channels: 1, sample_rate: 48_000)
        IO.stub(:popen, encoder_io) do
          rec.start
          rec.push("chunk1")
          rec.stop
        end

        assert_includes encoder_io.string, "chunk1"
      end

      test "stop without start is a no-op" do
        rec = RecordingEncoder.new(path: "/tmp/rec.m4a", channels: 1, sample_rate: 48_000)
        assert_nothing_raised { rec.stop }
      end

      test "push without start is a no-op" do
        rec = RecordingEncoder.new(path: "/tmp/rec.m4a", channels: 1, sample_rate: 48_000)
        assert_nothing_raised { rec.push("data") }
      end

      test "drain logs warning when encoder raises IOError" do
        encoder_io = Object.new
        encoder_io.define_singleton_method(:pid) { 99_999 }
        encoder_io.define_singleton_method(:write) { |_| raise IOError, "broken pipe" }
        encoder_io.define_singleton_method(:close) { nil }

        rec = RecordingEncoder.new(path: "/tmp/rec.m4a", channels: 1, sample_rate: 48_000)
        logged = []
        logger = Logger.new(StringIO.new)
        logger.define_singleton_method(:warn) { |msg| logged << msg }

        EarlScribe.stub(:logger, logger) do
          IO.stub(:popen, encoder_io) do
            rec.start
            rec.push("data")
            rec.stop
          end
        end

        assert_includes logged.first, "Recording may be incomplete"
      end
    end
  end
end
