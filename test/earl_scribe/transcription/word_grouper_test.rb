# frozen_string_literal: true

require "test_helper"
require "json"

module EarlScribe
  module Transcription
    class WordGrouperTest < Minitest::Test
      test "groups words by speaker" do
        json = read_fixture("transcription/deepgram_multi_speaker.json")
        words = JSON.parse(json).dig("channel", "alternatives", 0, "words")

        segments = EarlScribe::Transcription::WordGrouper.group(words)
        assert_equal 2, segments.size
        assert_equal "Speaker 0", segments[0].speaker
        assert_equal "Hello everyone.", segments[0].text
        assert_equal "Speaker 1", segments[1].speaker
        assert_equal "Thanks for joining.", segments[1].text
      end

      test "single speaker produces one segment" do
        json = read_fixture("transcription/deepgram_result.json")
        words = JSON.parse(json).dig("channel", "alternatives", 0, "words")

        segments = EarlScribe::Transcription::WordGrouper.group(words)
        assert_equal 1, segments.size
        assert_equal "Speaker 0", segments[0].speaker
      end

      test "applies speaker prefix" do
        words = [{ "word" => "hi", "punctuated_word" => "Hi", "speaker" => 0 }]
        segments = EarlScribe::Transcription::WordGrouper.group(words, speaker_prefix: "Meeting")

        assert_equal "Meeting Speaker 0", segments[0].speaker
      end

      test "returns empty array for nil words" do
        assert_equal [], EarlScribe::Transcription::WordGrouper.group(nil)
      end

      test "returns empty array for empty words" do
        assert_equal [], EarlScribe::Transcription::WordGrouper.group([])
      end

      test "handles words without speaker field" do
        words = [{ "word" => "hello", "punctuated_word" => "Hello" }]
        segments = EarlScribe::Transcription::WordGrouper.group(words)

        assert_equal 1, segments.size
        assert_equal "Speaker 0", segments[0].speaker
      end

      test "handles words without punctuated_word" do
        words = [{ "word" => "hello", "speaker" => 0 }]
        segments = EarlScribe::Transcription::WordGrouper.group(words)

        assert_equal "hello", segments[0].text
      end

      test "results are Result structs" do
        words = [{ "word" => "test", "speaker" => 0 }]
        segments = EarlScribe::Transcription::WordGrouper.group(words)

        assert_instance_of EarlScribe::Transcription::Result, segments[0]
      end

      test "results include start_time and end_time from word timestamps" do
        json = read_fixture("transcription/deepgram_multi_speaker.json")
        words = JSON.parse(json).dig("channel", "alternatives", 0, "words")

        segments = EarlScribe::Transcription::WordGrouper.group(words)

        assert_in_delta 0.0, segments[0].start_time, 0.001
        assert_in_delta 1.0, segments[0].end_time, 0.001
        assert_in_delta 1.5, segments[1].start_time, 0.001
        assert_in_delta 2.8, segments[1].end_time, 0.001
      end

      test "start_time and end_time are nil when words lack timestamps" do
        words = [{ "word" => "hello", "speaker" => 0 }]
        segments = EarlScribe::Transcription::WordGrouper.group(words)

        assert_nil segments[0].start_time
        assert_nil segments[0].end_time
      end
    end
  end
end
