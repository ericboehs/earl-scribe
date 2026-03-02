# frozen_string_literal: true

module EarlScribe
  # ENV-based configuration for API keys and external tool paths
  class Config
    DEFAULTS = {
      "DEEPGRAM_API_KEY" => nil,
      "DEEPGRAM_MIP_OPT_OUT" => nil,
      "WHISPER_CPP_PATH" => "whisper-cpp",
      "WHISPER_MODELS_DIR" => nil,
      "WHISPER_MODEL" => "large-v3",
      "AUDIO_DEVICE" => "Meeting",
      "AUDIO_CHUNK_SECONDS" => "10"
    }.freeze

    def self.get(key)
      ENV.fetch(key, DEFAULTS[key])
    end

    def self.deepgram_api_key
      get("DEEPGRAM_API_KEY")
    end

    def self.whisper_cpp_path
      get("WHISPER_CPP_PATH")
    end

    def self.whisper_models_dir
      get("WHISPER_MODELS_DIR")
    end

    def self.whisper_model
      get("WHISPER_MODEL")
    end

    def self.audio_device
      get("AUDIO_DEVICE")
    end

    def self.audio_chunk_seconds
      get("AUDIO_CHUNK_SECONDS").to_i
    end

    def self.deepgram_mip_opt_out?
      %w[1 true yes].include?(get("DEEPGRAM_MIP_OPT_OUT")&.downcase)
    end
  end
end
