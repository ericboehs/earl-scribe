# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "earl_scribe/cli/rerun_audio"

module EarlScribe
  module Cli
    class RerunAudioTest < Minitest::Test
      def setup
        @dir = Dir.mktmpdir
      end

      def teardown
        FileUtils.rm_rf(@dir)
      end

      def fake_status(success:)
        status = Object.new
        status.define_singleton_method(:success?) { success }
        status
      end

      def test_normalize_wav_returns_nil_for_nil_input
        assert_nil RerunAudio.normalize_wav(nil)
      end

      def test_normalize_wav_returns_nil_for_missing_file
        assert_nil RerunAudio.normalize_wav("/nonexistent.wav")
      end

      def test_normalize_wav_returns_path_on_success
        src = File.join(@dir, "in.wav")
        File.write(src, "x")
        Open3.stub(:capture3, lambda { |*args|
          File.write(args.last, "normalized") # ffmpeg writes the output
          ["", "", fake_status(success: true)]
        }) do
          result = RerunAudio.normalize_wav(src)
          assert_equal "#{src}.norm.wav", result
        end
      end

      def test_normalize_wav_cleans_up_and_returns_nil_on_failure
        src = File.join(@dir, "in.wav")
        File.write(src, "x")
        Open3.stub(:capture3, lambda { |*args|
          File.write(args.last, "partial")
          ["", "boom", fake_status(success: false)]
        }) do
          assert_nil RerunAudio.normalize_wav(src)
          assert_not File.exist?("#{src}.norm.wav")
        end
      end

      def test_encode_m4a_silent_on_success
        Open3.stub(:capture3, ->(*_) { ["", "", fake_status(success: true)] }) do
          _out, err = capture_io { RerunAudio.encode_m4a("/x.wav", "/y.m4a") }
          assert_empty err
        end
      end

      def test_encode_m4a_warns_on_failure
        Open3.stub(:capture3, ->(*_) { ["", "moov atom not found", fake_status(success: false)] }) do
          _out, err = capture_io { RerunAudio.encode_m4a("/x.wav", "/y.m4a") }
          assert_match(/ffmpeg encode failed/, err)
        end
      end

      def test_wav_duration_sec_returns_nil_for_short_file
        path = File.join(@dir, "tiny.wav")
        File.write(path, "x")
        assert_nil RerunAudio.wav_duration_sec(path)
      end

      def test_wav_duration_sec_parses_data_chunk_size
        path = File.join(@dir, "ok.wav")
        # Build a 44-byte header with data_bytes=32000 (1s @ 16k Int16 mono)
        header = "RIFF".dup << [36 + 32_000].pack("V") << "WAVEfmt "
        header << [16].pack("V") << [1].pack("v") << [1].pack("v")
        header << [16_000].pack("V") << [32_000].pack("V") << [2].pack("v") << [16].pack("v")
        header << "data" << [32_000].pack("V")
        File.binwrite(path, header)
        assert_in_delta 1.0, RerunAudio.wav_duration_sec(path), 1e-6
      end
    end
  end
end
