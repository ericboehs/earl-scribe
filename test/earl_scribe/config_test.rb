# frozen_string_literal: true

require "test_helper"

module EarlScribe
  class ConfigTest < Minitest::Test
    test "get returns env var when set" do
      ENV["DEEPGRAM_API_KEY"] = "test-key-123"
      assert_equal "test-key-123", EarlScribe::Config.get("DEEPGRAM_API_KEY")
    ensure
      ENV.delete("DEEPGRAM_API_KEY")
    end

    test "get returns default when env var not set" do
      ENV.delete("EARL_SCRIBE_AUDIOTEE_PATH")
      assert_equal "audiotee", EarlScribe::Config.get("EARL_SCRIBE_AUDIOTEE_PATH")
    end

    test "get returns nil for unknown key with no default" do
      ENV.delete("DEEPGRAM_API_KEY")
      assert_nil EarlScribe::Config.get("DEEPGRAM_API_KEY")
    end

    test "deepgram_api_key reads from env" do
      ENV["DEEPGRAM_API_KEY"] = "dg-key"
      assert_equal "dg-key", EarlScribe::Config.deepgram_api_key
    ensure
      ENV.delete("DEEPGRAM_API_KEY")
    end

    test "audio_device has default" do
      ENV.delete("AUDIO_DEVICE")
      assert_equal "Meeting", EarlScribe::Config.audio_device
    end

    test "asr_bin has default" do
      ENV.delete("EARL_SCRIBE_ASR_BIN")
      assert_equal "earl-scribe-asr", EarlScribe::Config.asr_bin
    end

    test "asr_chunk_ms returns integer with default" do
      ENV.delete("EARL_SCRIBE_ASR_CHUNK_MS")
      assert_equal 1280, EarlScribe::Config.asr_chunk_ms
    end

    test "rerun_chunk_ms returns integer with default" do
      ENV.delete("EARL_SCRIBE_RERUN_CHUNK_MS")
      assert_equal 320, EarlScribe::Config.rerun_chunk_ms
    end

    test "rerun_model defaults to batch" do
      ENV.delete("EARL_SCRIBE_RERUN_MODEL")
      assert_equal "batch", EarlScribe::Config.rerun_model
    end

    test "rerun_model can be overridden via env" do
      ENV["EARL_SCRIBE_RERUN_MODEL"] = "streaming"
      assert_equal "streaming", EarlScribe::Config.rerun_model
    ensure
      ENV.delete("EARL_SCRIBE_RERUN_MODEL")
    end

    test "llama_bin has default" do
      ENV.delete("EARL_SCRIBE_LLAMA_BIN")
      assert_equal "llama-cli", EarlScribe::Config.llama_bin
    end

    test "qwen_model returns nil by default" do
      ENV.delete("EARL_SCRIBE_QWEN_MODEL")
      assert_nil EarlScribe::Config.qwen_model
    end

    test "summary_interval_sec returns integer with default" do
      ENV.delete("EARL_SCRIBE_SUMMARY_INTERVAL_SEC")
      assert_equal 180, EarlScribe::Config.summary_interval_sec
    end

    test "summarize? defaults to false" do
      ENV.delete("EARL_SCRIBE_SUMMARIZE")
      assert_not EarlScribe::Config.summarize?
    end

    test "summarize? respects explicit enable via env" do
      ENV["EARL_SCRIBE_SUMMARIZE"] = "1"
      assert EarlScribe::Config.summarize?
    ensure
      ENV.delete("EARL_SCRIBE_SUMMARIZE")
    end

    test "summary_prompt_path returns nil by default" do
      ENV.delete("EARL_SCRIBE_SUMMARY_PROMPT")
      assert_nil EarlScribe::Config.summary_prompt_path
    end

    test "deepgram_mip_opt_out? returns false by default" do
      ENV.delete("DEEPGRAM_MIP_OPT_OUT")
      assert_not EarlScribe::Config.deepgram_mip_opt_out?
    end

    test "deepgram_mip_opt_out? accepts 1, true, yes case-insensitively" do
      %w[1 true TRUE yes Yes].each do |val|
        ENV["DEEPGRAM_MIP_OPT_OUT"] = val
        assert EarlScribe::Config.deepgram_mip_opt_out?, "Expected true for #{val.inspect}"
      end
    ensure
      ENV.delete("DEEPGRAM_MIP_OPT_OUT")
    end

    test "deepgram_mip_opt_out? returns false for other values" do
      ENV["DEEPGRAM_MIP_OPT_OUT"] = "no"
      assert_not EarlScribe::Config.deepgram_mip_opt_out?
    ensure
      ENV.delete("DEEPGRAM_MIP_OPT_OUT")
    end

    test "audio_mic has default" do
      ENV.delete("AUDIO_MIC")
      assert_equal "default", EarlScribe::Config.audio_mic
    end

    test "audio_mic reads from env" do
      ENV["AUDIO_MIC"] = "Streamer X Main"
      assert_equal "Streamer X Main", EarlScribe::Config.audio_mic
    ensure
      ENV.delete("AUDIO_MIC")
    end

    test "audio_device_explicit? is false when env var unset" do
      ENV.delete("AUDIO_DEVICE")
      assert_not EarlScribe::Config.audio_device_explicit?
    end

    test "audio_device_explicit? is true when env var set" do
      ENV["AUDIO_DEVICE"] = "Loopback Meeting"
      assert EarlScribe::Config.audio_device_explicit?
    ensure
      ENV.delete("AUDIO_DEVICE")
    end

    test "audiotee_path has default" do
      ENV.delete("EARL_SCRIBE_AUDIOTEE_PATH")
      assert_equal "audiotee", EarlScribe::Config.audiotee_path
    end

    test "audiotee_path reads from env" do
      ENV["EARL_SCRIBE_AUDIOTEE_PATH"] = "/opt/audiotee"
      assert_equal "/opt/audiotee", EarlScribe::Config.audiotee_path
    ensure
      ENV.delete("EARL_SCRIBE_AUDIOTEE_PATH")
    end

    test "calendar_names returns nil by default" do
      ENV.delete("EARL_SCRIBE_CALENDAR_NAMES")
      assert_nil EarlScribe::Config.calendar_names
    end

    test "calendar_names splits comma-separated values" do
      ENV["EARL_SCRIBE_CALENDAR_NAMES"] = "work@example.com, personal@example.com"
      assert_equal %w[work@example.com personal@example.com], EarlScribe::Config.calendar_names
    ensure
      ENV.delete("EARL_SCRIBE_CALENDAR_NAMES")
    end
  end
end
