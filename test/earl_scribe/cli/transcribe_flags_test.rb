# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Cli
    class TranscribeFlagsTest < Minitest::Test
      test "device defaults to nil when env not explicit" do
        EarlScribe::Config.stub(:audio_device_explicit?, false) do
          opts = TranscribeFlags.parse([])
          assert_nil opts[:device]
        end
      end

      test "device falls back to env when explicit" do
        EarlScribe::Config.stub(:audio_device_explicit?, true) do
          EarlScribe::Config.stub(:audio_device, "EnvMic") do
            opts = TranscribeFlags.parse([])
            assert_equal "EnvMic", opts[:device]
          end
        end
      end

      test "device flag value wins over env default" do
        opts = TranscribeFlags.parse(["--device", "Mic2"])
        assert_equal "Mic2", opts[:device]
      end

      test "threshold parses as float when provided" do
        opts = TranscribeFlags.parse(["--threshold", "0.42"])
        assert_in_delta 0.42, opts[:threshold], 1e-6
      end

      test "threshold is nil when omitted" do
        opts = TranscribeFlags.parse([])
        assert_nil opts[:threshold]
      end

      test "diarize defaults to true" do
        opts = TranscribeFlags.parse([])
        assert_equal true, opts[:diarize]
      end

      test "--no-diarize disables diarization" do
        opts = TranscribeFlags.parse(["--no-diarize"])
        assert_equal false, opts[:diarize]
      end

      test "--diar-debug enables diarizer debug output" do
        opts = TranscribeFlags.parse(["--diar-debug"])
        assert_equal true, opts[:diar_debug]
      end

      test "summary-interval-sec falls back to Config when omitted" do
        EarlScribe::Config.stub(:summary_interval_sec, 240) do
          opts = TranscribeFlags.parse([])
          assert_equal 240, opts[:summary_interval_sec]
        end
      end

      test "summary-interval-sec from CLI takes precedence" do
        opts = TranscribeFlags.parse(["--summary-interval-sec", "60"])
        assert_equal 60, opts[:summary_interval_sec]
      end

      test "summary defaults to off" do
        EarlScribe::Config.stub(:summarize?, false) do
          opts = TranscribeFlags.parse([])
          assert_equal false, opts[:summarize]
        end
      end

      test "--summary enables summarization" do
        EarlScribe::Config.stub(:summarize?, false) do
          opts = TranscribeFlags.parse(["--summary"])
          assert_equal true, opts[:summarize]
        end
      end

      test "cloud flag is recognized" do
        opts = TranscribeFlags.parse(["--cloud"])
        assert_equal true, opts[:cloud]
      end

      test "stereo flag is recognized" do
        opts = TranscribeFlags.parse(["--stereo"])
        assert_equal true, opts[:stereo]
      end

      test "no-identify flag flips identify to false" do
        opts = TranscribeFlags.parse(["--no-identify"])
        assert_equal false, opts[:identify]
      end

      test "record flag enables recording" do
        opts = TranscribeFlags.parse(["--record"])
        assert_equal true, opts[:record]
      end

      test "no-mic flag toggles single-source capture" do
        opts = TranscribeFlags.parse(["--no-mic"])
        assert_equal true, opts[:no_mic]
      end

      test "native flag defaults to false" do
        opts = TranscribeFlags.parse([])
        assert_equal false, opts[:native]
      end

      test "--native enables native capture" do
        opts = TranscribeFlags.parse(["--native"])
        assert_equal true, opts[:native]
      end

      test "rerun defaults to false" do
        opts = TranscribeFlags.parse([])
        assert_equal false, opts[:rerun]
      end

      test "--rerun enables second-pass" do
        opts = TranscribeFlags.parse(["--rerun"])
        assert_equal true, opts[:rerun]
      end

      test "value flags after another flag are not flagged unknown" do
        _stdout, stderr = capture_io { TranscribeFlags.parse(["--mic", "Mic A", "--title", "Foo"]) }
        assert_not_includes stderr, "unknown flag"
      end

      test "warns on unknown flag" do
        _stdout, stderr = capture_io { TranscribeFlags.parse(["--bogus"]) }
        assert_includes stderr, "unknown flag"
        assert_includes stderr, "--bogus"
      end
    end
  end
end
