# frozen_string_literal: true

require "open3"

module EarlScribe
  module Transcription
    # Transcribes audio files via whisper.cpp subprocess
    class Whisper
      attr_reader :binary_path, :model_path

      def initialize(binary_path: Config.whisper_cpp_path, model_path: resolve_model_path)
        @binary_path = binary_path
        @model_path = model_path
      end

      def transcribe(wav_path)
        validate_prerequisites(wav_path)
        raw = run_whisper(wav_path)
        HallucinationFilter.filter(raw)
      end

      def available?
        File.executable?(binary_path) && File.exist?(model_path)
      end

      def self.resolve_model_path
        models_dir = Config.whisper_models_dir
        return "" unless models_dir

        File.join(models_dir, "ggml-#{Config.whisper_model}.bin")
      end

      private

      def validate_prerequisites(wav_path)
        raise Error, "whisper.cpp not found at #{binary_path}" unless File.executable?(binary_path)
        raise Error, "Model not found at #{model_path}" unless File.exist?(model_path)
        raise Error, "Audio file not found: #{wav_path}" unless File.exist?(wav_path)
      end

      def run_whisper(wav_path)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        stdout, _stderr, _status = Open3.capture3(
          binary_path, "-m", model_path, "-f", wav_path,
          "--no-timestamps", "--no-prints", "-t", "4"
        )
        stdout.strip
      end
    end
  end
end
