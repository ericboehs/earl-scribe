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
      ENV.delete("WHISPER_CPP_PATH")
      assert_equal "whisper-cpp", EarlScribe::Config.get("WHISPER_CPP_PATH")
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

    test "whisper_cpp_path has default" do
      ENV.delete("WHISPER_CPP_PATH")
      assert_equal "whisper-cpp", EarlScribe::Config.whisper_cpp_path
    end

    test "whisper_models_dir returns nil by default" do
      ENV.delete("WHISPER_MODELS_DIR")
      assert_nil EarlScribe::Config.whisper_models_dir
    end

    test "whisper_model has default" do
      ENV.delete("WHISPER_MODEL")
      assert_equal "large-v3", EarlScribe::Config.whisper_model
    end

    test "audio_device has default" do
      ENV.delete("AUDIO_DEVICE")
      assert_equal "Meeting", EarlScribe::Config.audio_device
    end

    test "audio_chunk_seconds returns integer" do
      ENV.delete("AUDIO_CHUNK_SECONDS")
      assert_equal 10, EarlScribe::Config.audio_chunk_seconds
    end

    test "audio_chunk_seconds reads from env" do
      ENV["AUDIO_CHUNK_SECONDS"] = "30"
      assert_equal 30, EarlScribe::Config.audio_chunk_seconds
    ensure
      ENV.delete("AUDIO_CHUNK_SECONDS")
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
  end
end
