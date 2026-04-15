# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Cli
    class TranscribeBannerTest < Minitest::Test
      test "prints engine and device info to stderr" do
        _stdout, stderr = capture_io do
          TranscribeBanner.print(engine: "Deepgram Nova-3", mode: "stereo",
                                 id_status: "enabled", device_label: "[0] TestMic")
        end

        assert_includes stderr, "Deepgram Nova-3"
        assert_includes stderr, "TestMic"
        assert_includes stderr, "stereo"
        assert_includes stderr, "Speaker ID: enabled"
      end

      test "includes recording path when provided" do
        _stdout, stderr = capture_io do
          TranscribeBanner.print(engine: "whisper.cpp", mode: "local", id_status: "disabled",
                                 device_label: "[1] Mic2",
                                 session: { recording: "earl-scribe-20260302_140000.m4a" })
        end

        assert_includes stderr, "Recording:  earl-scribe-20260302_140000.m4a"
      end

      test "omits recording line when nil" do
        _stdout, stderr = capture_io do
          TranscribeBanner.print(engine: "Deepgram Nova-3", mode: "stereo",
                                 id_status: "disabled", device_label: "[0] TestMic")
        end

        assert_not_includes stderr, "Recording:"
      end

      test "includes transcript path when provided" do
        _stdout, stderr = capture_io do
          TranscribeBanner.print(engine: "Deepgram Nova-3", mode: "stereo", id_status: "disabled",
                                 device_label: "[0] TestMic",
                                 session: { transcript: "/tmp/earl-scribe-20260302_140000.txt" })
        end

        assert_includes stderr, "Transcript: /tmp/earl-scribe-20260302_140000.txt"
      end

      test "omits transcript line when not provided" do
        _stdout, stderr = capture_io do
          TranscribeBanner.print(engine: "Deepgram Nova-3", mode: "stereo",
                                 id_status: "disabled", device_label: "[0] TestMic")
        end

        assert_not_includes stderr, "Transcript:"
      end

      test "shows custom device label like System Audio" do
        _stdout, stderr = capture_io do
          TranscribeBanner.print(engine: "Deepgram Nova-3", mode: "system audio (mono)",
                                 id_status: "disabled", device_label: "System Audio (audiotee)")
        end

        assert_includes stderr, "System Audio (audiotee)"
      end
    end
  end
end
