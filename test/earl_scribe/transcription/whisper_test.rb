# frozen_string_literal: true

require "test_helper"
require "open3"
require "tempfile"

module EarlScribe
  module Transcription
    class WhisperTest < Minitest::Test
      setup do
        @tmp_dir = Dir.mktmpdir("whisper_test")
        @binary = File.join(@tmp_dir, "whisper-cli")
        File.write(@binary, "#!/bin/sh\n")
        File.chmod(0o755, @binary)
        @model = File.join(@tmp_dir, "model.bin")
        File.write(@model, "model")
        @wav = File.join(@tmp_dir, "test.wav")
        File.write(@wav, "RIFF")
      end

      teardown do
        FileUtils.rm_rf(@tmp_dir)
      end

      test "transcribe returns filtered text" do
        whisper = Whisper.new(binary_path: @binary, model_path: @model)
        success = mock_status(true)

        Open3.stub(:capture3, [" Hello everyone, welcome.\n", "", success]) do
          result = whisper.transcribe(@wav)
          assert_equal "Hello everyone, welcome.", result
        end
      end

      test "transcribe filters hallucinations" do
        whisper = Whisper.new(binary_path: @binary, model_path: @model)
        success = mock_status(true)

        Open3.stub(:capture3, ["[BLANK_AUDIO]\n", "", success]) do
          result = whisper.transcribe(@wav)
          assert_nil result
        end
      end

      test "transcribe raises when binary not found" do
        whisper = Whisper.new(binary_path: "/nonexistent", model_path: @model)

        error = assert_raises(EarlScribe::Error) { whisper.transcribe(@wav) }
        assert_includes error.message, "whisper.cpp not found"
      end

      test "transcribe raises when model not found" do
        whisper = Whisper.new(binary_path: @binary, model_path: "/nonexistent.bin")

        error = assert_raises(EarlScribe::Error) { whisper.transcribe(@wav) }
        assert_includes error.message, "Model not found"
      end

      test "transcribe raises when audio file not found" do
        whisper = Whisper.new(binary_path: @binary, model_path: @model)

        error = assert_raises(EarlScribe::Error) { whisper.transcribe("/nonexistent.wav") }
        assert_includes error.message, "Audio file not found"
      end

      test "available? returns false when binary missing" do
        whisper = Whisper.new(binary_path: "/nonexistent", model_path: "/nonexistent")
        assert_not whisper.available?
      end

      test "resolve_model_path returns empty when no models dir" do
        ENV.delete("WHISPER_MODELS_DIR")
        assert_equal "", Whisper.resolve_model_path
      end

      test "resolve_model_path builds path from config" do
        ENV["WHISPER_MODELS_DIR"] = "/tmp/models"
        ENV["WHISPER_MODEL"] = "base.en"
        path = Whisper.resolve_model_path
        assert_equal "/tmp/models/ggml-base.en.bin", path
      ensure
        ENV.delete("WHISPER_MODELS_DIR")
        ENV.delete("WHISPER_MODEL")
      end

      private

      def mock_status(success)
        status = Minitest::Mock.new
        status.expect(:success?, success)
        status
      end
    end
  end
end
