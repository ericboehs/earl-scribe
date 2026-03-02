# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Transcription
    class ResultParserTest < Minitest::Test
      test "parses final result" do
        json = read_fixture("transcription/deepgram_result.json")
        result = EarlScribe::Transcription::ResultParser.parse(json)

        assert_not_nil result
        assert_equal 0, result[:channel_index]
        assert_equal "Hello everyone, welcome to the meeting.", result[:transcript]
        assert_equal 6, result[:words].size
      end

      test "returns nil for non-final result" do
        json = '{"type": "Results", "is_final": false, "channel": {"alternatives": [{"transcript": "hi"}]}}'
        assert_nil EarlScribe::Transcription::ResultParser.parse(json)
      end

      test "returns nil for non-Results type" do
        json = '{"type": "Metadata", "is_final": true}'
        assert_nil EarlScribe::Transcription::ResultParser.parse(json)
      end

      test "returns nil for empty transcript" do
        json = '{"type": "Results", "is_final": true, "channel": {"alternatives": [{"transcript": "  ", "words": []}]}}'
        assert_nil EarlScribe::Transcription::ResultParser.parse(json)
      end

      test "returns nil when no alternatives" do
        json = '{"type": "Results", "is_final": true, "channel": {"alternatives": []}}'
        assert_nil EarlScribe::Transcription::ResultParser.parse(json)
      end

      test "handles missing channel_index" do
        json = '{"type": "Results", "is_final": true, ' \
               '"channel": {"alternatives": [{"transcript": "hello", "words": []}]}}'
        result = EarlScribe::Transcription::ResultParser.parse(json)

        assert_equal 0, result[:channel_index]
      end

      test "includes words array" do
        json = read_fixture("transcription/deepgram_multi_speaker.json")
        result = EarlScribe::Transcription::ResultParser.parse(json)

        assert_equal 5, result[:words].size
        assert_equal 0, result[:words].first["speaker"]
        assert_equal 1, result[:words].last["speaker"]
      end
    end
  end
end
