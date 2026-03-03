# frozen_string_literal: true

require "test_helper"

class EarlScribeTest < Minitest::Test
  test "VERSION is set" do
    assert_not_nil EarlScribe::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, EarlScribe::VERSION)
  end

  test "config_root returns expected path" do
    expected = File.join(Dir.home, ".config", "earl-scribe")
    assert_equal expected, EarlScribe.config_root
  end

  test "logger returns a Logger instance" do
    assert_instance_of Logger, EarlScribe.logger
  end

  test "logger can be assigned" do
    original = EarlScribe.logger
    custom = Logger.new($stdout)
    EarlScribe.logger = custom
    assert_same custom, EarlScribe.logger
  ensure
    EarlScribe.logger = original
  end

  test "Error is a StandardError subclass" do
    assert EarlScribe::Error < StandardError
  end

  test "data_dir defaults to ~/.local/share/earl-scribe" do
    orig_data = ENV.delete("EARL_SCRIBE_DATA_DIR")
    orig_xdg = ENV.delete("XDG_DATA_HOME")
    expected = File.join(Dir.home, ".local", "share", "earl-scribe")
    assert_equal expected, EarlScribe.data_dir
  ensure
    ENV["EARL_SCRIBE_DATA_DIR"] = orig_data
    ENV["XDG_DATA_HOME"] = orig_xdg
  end

  test "data_dir respects EARL_SCRIBE_DATA_DIR" do
    orig = ENV.fetch("EARL_SCRIBE_DATA_DIR", nil)
    ENV["EARL_SCRIBE_DATA_DIR"] = "/custom/data"
    assert_equal "/custom/data", EarlScribe.data_dir
  ensure
    ENV["EARL_SCRIBE_DATA_DIR"] = orig
  end

  test "data_dir respects XDG_DATA_HOME" do
    orig_data = ENV.delete("EARL_SCRIBE_DATA_DIR")
    orig_xdg = ENV.fetch("XDG_DATA_HOME", nil)
    ENV["XDG_DATA_HOME"] = "/xdg/data"
    assert_equal "/xdg/data/earl-scribe", EarlScribe.data_dir
  ensure
    ENV["EARL_SCRIBE_DATA_DIR"] = orig_data
    ENV["XDG_DATA_HOME"] = orig_xdg
  end
end
