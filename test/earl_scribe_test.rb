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
end
