# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Transcription
    class LocalStreamEventParserTest < Minitest::Test
      test "feed accumulates partial lines until newline" do
        parser = LocalStreamEventParser.new
        events = parser.feed('{"type":"partial",')
        assert_empty events

        events = parser.feed("\"text\":\"hi\",\"wall_ms\":10}\n")
        assert_equal 1, events.size
        assert_equal :partial, events.first[:event]
      end

      test "eou event yields a result hash with synthesized words" do
        parser = LocalStreamEventParser.new
        line = "{\"type\":\"eou\",\"text\":\"hello world\",\"audio_sec\":2.5,\"wall_ms\":100}\n"
        event = parser.feed(line).first

        assert_equal :eou, event[:event]
        result = event[:result]
        assert_equal 0, result[:channel_index]
        assert_equal "hello world", result[:transcript]
        word = result[:words].first
        assert_in_delta 0.0, word["start"], 1e-6
        assert_in_delta 2.5, word["end"], 1e-6
        assert_equal 0, word["speaker"]
        assert_equal "hello world", word["punctuated_word"]
      end

      test "consecutive eou events advance the audio cursor" do
        parser = LocalStreamEventParser.new
        first = parser.feed("{\"type\":\"eou\",\"text\":\"one\",\"audio_sec\":3}\n").first
        second = parser.feed("{\"type\":\"eou\",\"text\":\"two\",\"audio_sec\":7}\n").first

        assert_in_delta 0.0, first[:result][:words].first["start"], 1e-6
        assert_in_delta 3.0, first[:result][:words].first["end"], 1e-6
        assert_in_delta 3.0, second[:result][:words].first["start"], 1e-6
        assert_in_delta 7.0, second[:result][:words].first["end"], 1e-6
      end

      test "empty eou text does not produce a result" do
        parser = LocalStreamEventParser.new
        event = parser.feed("{\"type\":\"eou\",\"text\":\"   \",\"audio_sec\":1}\n").first
        assert_equal :eou, event[:event]
        assert_nil event[:result]
      end

      test "missing audio_sec falls back to last cursor" do
        parser = LocalStreamEventParser.new
        parser.feed("{\"type\":\"eou\",\"text\":\"first\",\"audio_sec\":1.5}\n")
        event = parser.feed("{\"type\":\"eou\",\"text\":\"second\"}\n").first
        word = event[:result][:words].first
        assert_in_delta 1.5, word["start"], 1e-6
        assert_in_delta 1.5, word["end"], 1e-6
      end

      test "malformed JSON yields a malformed event" do
        parser = LocalStreamEventParser.new
        events = parser.feed("not-json\n")
        assert_equal :malformed, events.first[:event]
        assert_equal "not-json", events.first[:data]["line"]
      end

      test "non-eou control events pass through unchanged" do
        parser = LocalStreamEventParser.new
        line = "{\"type\":\"models_loaded\",\"elapsed_sec\":0.4}\n"
        event = parser.feed(line).first
        assert_equal :models_loaded, event[:event]
        assert_in_delta 0.4, event[:data]["elapsed_sec"], 1e-6
        assert_nil event[:result]
      end

      test "skips blank lines" do
        parser = LocalStreamEventParser.new
        events = parser.feed("\n\n")
        assert_empty events
      end

      test "final event yields tail segment when text extends past last EOU" do
        parser = LocalStreamEventParser.new
        parser.feed("{\"type\":\"eou\",\"text\":\"hello world\",\"audio_sec\":2.0}\n")
        line = "{\"type\":\"final\",\"text\":\"hello world and goodbye\",\"audio_duration_sec\":3.5}\n"
        event = parser.feed(line).first

        assert_equal :final, event[:event]
        result = event[:result]
        assert_equal "and goodbye", result[:transcript]
        assert_in_delta 2.0, result[:words].first["start"], 1e-6
        assert_in_delta 3.5, result[:words].first["end"], 1e-6
      end

      test "final event with no tail yields no result" do
        parser = LocalStreamEventParser.new
        parser.feed("{\"type\":\"eou\",\"text\":\"complete sentence\",\"audio_sec\":1.0}\n")
        line = "{\"type\":\"final\",\"text\":\"complete sentence\",\"audio_duration_sec\":1.0}\n"
        event = parser.feed(line).first
        assert_equal :final, event[:event]
        assert_nil event[:result]
      end

      test "final event when no EOUs were emitted treats whole transcript as tail" do
        parser = LocalStreamEventParser.new
        line = "{\"type\":\"final\",\"text\":\"only said this\",\"audio_duration_sec\":2.0}\n"
        event = parser.feed(line).first
        assert_equal "only said this", event[:result][:transcript]
        assert_in_delta 0.0, event[:result][:words].first["start"], 1e-6
        assert_in_delta 2.0, event[:result][:words].first["end"], 1e-6
      end

      test "final event when text diverges from accumulated falls back to full text" do
        parser = LocalStreamEventParser.new
        parser.feed("{\"type\":\"eou\",\"text\":\"foo\",\"audio_sec\":1.0}\n")
        line = "{\"type\":\"final\",\"text\":\"baz qux\",\"audio_duration_sec\":2.0}\n"
        event = parser.feed(line).first
        assert_equal "baz qux", event[:result][:transcript]
      end
    end
  end
end
