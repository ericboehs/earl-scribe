# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Transcription
    class ResultTest < Minitest::Test
      test "to_s with speaker" do
        result = EarlScribe::Transcription::Result.new(speaker: "Alice", text: "Hello world")
        assert_equal "Alice: Hello world", result.to_s
      end

      test "to_s without speaker" do
        result = EarlScribe::Transcription::Result.new(text: "Hello world")
        assert_equal "Hello world", result.to_s
      end

      test "duration calculates correctly" do
        result = EarlScribe::Transcription::Result.new(start_time: 1.0, end_time: 3.5)
        assert_in_delta 2.5, result.duration
      end

      test "duration returns 0 when times are nil" do
        result = EarlScribe::Transcription::Result.new(text: "test")
        assert_equal 0, result.duration
      end

      test "all fields accessible" do
        result = EarlScribe::Transcription::Result.new(
          speaker: "Bob", text: "Hi", start_time: 0.0, end_time: 1.0, channel: 0
        )
        assert_equal "Bob", result.speaker
        assert_equal "Hi", result.text
        assert_in_delta 0.0, result.start_time
        assert_in_delta 1.0, result.end_time
        assert_equal 0, result.channel
      end
    end
  end
end
