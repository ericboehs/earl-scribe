# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Cli
    class TranscribeBannerTest < Minitest::Test
      test "prints engine and device info to stderr" do
        device = EarlScribe::Audio::Device::DeviceInfo.new(index: 0, name: "TestMic")

        _stdout, stderr = capture_io do
          TranscribeBanner.print(device, engine: "Deepgram Nova-3", mode: "stereo", id_status: "enabled")
        end

        assert_includes stderr, "Deepgram Nova-3"
        assert_includes stderr, "TestMic"
        assert_includes stderr, "stereo"
        assert_includes stderr, "Speaker ID: enabled"
      end

      test "includes recording path when provided" do
        device = EarlScribe::Audio::Device::DeviceInfo.new(index: 1, name: "Mic2")

        _stdout, stderr = capture_io do
          TranscribeBanner.print(device, engine: "whisper.cpp", mode: "local", id_status: "disabled",
                                         recording: "earl-scribe-20260302_140000.m4a")
        end

        assert_includes stderr, "Recording:  earl-scribe-20260302_140000.m4a"
      end

      test "omits recording line when nil" do
        device = EarlScribe::Audio::Device::DeviceInfo.new(index: 0, name: "TestMic")

        _stdout, stderr = capture_io do
          TranscribeBanner.print(device, engine: "Deepgram Nova-3", mode: "stereo", id_status: "disabled")
        end

        assert_not_includes stderr, "Recording:"
      end
    end
  end
end
