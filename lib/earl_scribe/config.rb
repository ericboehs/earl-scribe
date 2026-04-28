# frozen_string_literal: true

module EarlScribe
  class Config
    DEFAULTS = {
      "DEEPGRAM_API_KEY" => nil,
      "DEEPGRAM_MIP_OPT_OUT" => nil,
      "AUDIO_DEVICE" => "Meeting",
      "AUDIO_MIC" => "default",
      "AUDIO_MIC_GAIN_DB" => "12",
      "AUDIO_SAMPLE_RATE" => "48000",
      "EARL_SCRIBE_AUDIOTEE_PATH" => "audiotee",
      "EARL_SCRIBE_ASR_BIN" => "earl-scribe-asr",
      "EARL_SCRIBE_ASR_CHUNK_MS" => "1280",
      "EARL_SCRIBE_RERUN_CHUNK_MS" => "320",
      "EARL_SCRIBE_LLAMA_BIN" => "llama-cli",
      "EARL_SCRIBE_QWEN_MODEL" => nil,
      "EARL_SCRIBE_SUMMARY_INTERVAL_SEC" => "180",
      "EARL_SCRIBE_SUMMARIZE" => "0",
      "EARL_SCRIBE_SUMMARY_PROMPT" => nil,
      "EARL_SCRIBE_CALENDAR_NAMES" => nil
    }.freeze

    def self.get(key)
      ENV.fetch(key, DEFAULTS[key])
    end

    def self.deepgram_api_key
      get("DEEPGRAM_API_KEY")
    end

    def self.audio_device
      get("AUDIO_DEVICE")
    end

    def self.audio_device_explicit?
      ENV.key?("AUDIO_DEVICE")
    end

    def self.audio_mic
      get("AUDIO_MIC")
    end

    def self.mic_gain_db
      get("AUDIO_MIC_GAIN_DB").to_f
    end

    def self.audio_sample_rate
      get("AUDIO_SAMPLE_RATE").to_i
    end

    def self.audiotee_path
      get("EARL_SCRIBE_AUDIOTEE_PATH")
    end

    def self.asr_bin
      get("EARL_SCRIBE_ASR_BIN")
    end

    def self.asr_chunk_ms
      get("EARL_SCRIBE_ASR_CHUNK_MS").to_i
    end

    def self.rerun_chunk_ms
      get("EARL_SCRIBE_RERUN_CHUNK_MS").to_i
    end

    def self.llama_bin
      get("EARL_SCRIBE_LLAMA_BIN")
    end

    def self.qwen_model
      get("EARL_SCRIBE_QWEN_MODEL")
    end

    def self.summary_interval_sec
      get("EARL_SCRIBE_SUMMARY_INTERVAL_SEC").to_i
    end

    def self.summarize?
      %w[1 true yes].include?(get("EARL_SCRIBE_SUMMARIZE")&.downcase)
    end

    def self.summary_prompt_path
      get("EARL_SCRIBE_SUMMARY_PROMPT")
    end

    def self.calendar_names
      value = get("EARL_SCRIBE_CALENDAR_NAMES")
      value&.split(",")&.map(&:strip)
    end

    def self.deepgram_mip_opt_out?
      %w[1 true yes].include?(get("DEEPGRAM_MIP_OPT_OUT")&.downcase)
    end
  end
end
