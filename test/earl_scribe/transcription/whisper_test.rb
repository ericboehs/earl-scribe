# frozen_string_literal: true

require "test_helper"
require "open3"

module EarlScribe
  module Transcription
    class WhisperTest < Minitest::Test
      test "transcribe returns filtered text" do
        whisper = EarlScribe::Transcription::Whisper.new(binary_path: "/usr/bin/true", model_path: "/tmp/model.bin")
        success = mock_status(true)

        File.stub(:executable?, true) do
          File.stub(:exist?, true) do
            Open3.stub(:capture3, [" Hello everyone, welcome.\n", "", success]) do
              result = whisper.transcribe("/tmp/test.wav")
              assert_equal "Hello everyone, welcome.", result
            end
          end
        end
      end

      test "transcribe filters hallucinations" do
        whisper = EarlScribe::Transcription::Whisper.new(binary_path: "/usr/bin/true", model_path: "/tmp/model.bin")
        success = mock_status(true)

        File.stub(:executable?, true) do
          File.stub(:exist?, true) do
            Open3.stub(:capture3, ["[BLANK_AUDIO]\n", "", success]) do
              result = whisper.transcribe("/tmp/test.wav")
              assert_nil result
            end
          end
        end
      end

      test "transcribe raises when binary not found" do
        whisper = EarlScribe::Transcription::Whisper.new(binary_path: "/nonexistent", model_path: "/tmp/model.bin")

        error = assert_raises(EarlScribe::Error) { whisper.transcribe("/tmp/test.wav") }
        assert_includes error.message, "whisper.cpp not found"
      end

      test "transcribe raises when model not found" do
        whisper = EarlScribe::Transcription::Whisper.new(binary_path: "/usr/bin/true", model_path: "/nonexistent.bin")

        File.stub(:executable?, true) do
          error = assert_raises(EarlScribe::Error) { whisper.transcribe("/tmp/test.wav") }
          assert_includes error.message, "Model not found"
        end
      end

      test "transcribe raises when audio file not found" do
        whisper = EarlScribe::Transcription::Whisper.new(binary_path: "/usr/bin/true", model_path: "/tmp/model.bin")

        File.stub(:executable?, true) do
          stub_model = ->(*args) { args.first == "/tmp/model.bin" }
          File.stub(:exist?, stub_model) do
            error = assert_raises(EarlScribe::Error) { whisper.transcribe("/nonexistent.wav") }
            assert_includes error.message, "Audio file not found"
          end
        end
      end

      test "available? returns false when binary missing" do
        whisper = EarlScribe::Transcription::Whisper.new(binary_path: "/nonexistent", model_path: "/nonexistent")
        assert_not whisper.available?
      end

      test "resolve_model_path returns empty when no models dir" do
        ENV.delete("WHISPER_MODELS_DIR")
        assert_equal "", EarlScribe::Transcription::Whisper.resolve_model_path
      end

      test "resolve_model_path builds path from config" do
        ENV["WHISPER_MODELS_DIR"] = "/tmp/models"
        ENV["WHISPER_MODEL"] = "base.en"
        path = EarlScribe::Transcription::Whisper.resolve_model_path
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
