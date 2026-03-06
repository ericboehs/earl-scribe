# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Transcription
    class JsonlReaderTest < Minitest::Test
      test "parses metadata from JSONL file" do
        reader = JsonlReader.new(fixture_path("transcription/sample_transcript.jsonl"))
        assert_equal "EERT Standup", reader.meeting_title
        assert_equal "2026-03-03T13:00:00-06:00", reader.recorded_at
      end

      test "parses segments from JSONL file" do
        reader = JsonlReader.new(fixture_path("transcription/sample_transcript.jsonl"))
        assert_equal 4, reader.segments.size
        assert_equal "Speaker 0", reader.segments.first.speaker
        assert_equal "Hello everyone", reader.segments.first.text
        assert_in_delta 1.23, reader.segments.first.start_time
      end

      test "unidentified_speakers? returns true when present" do
        reader = JsonlReader.new(fixture_path("transcription/sample_transcript.jsonl"))
        assert reader.unidentified_speakers?
      end

      test "unidentified_speakers returns unique labels" do
        reader = JsonlReader.new(fixture_path("transcription/sample_transcript.jsonl"))
        labels = reader.unidentified_speakers
        assert_includes labels, "Speaker 0"
        assert_includes labels, "Speaker 1"
        assert_not_includes labels, "Alice"
      end

      test "segments_for_speaker returns matching segments" do
        reader = JsonlReader.new(fixture_path("transcription/sample_transcript.jsonl"))
        segs = reader.segments_for_speaker("Speaker 0")
        assert_equal 2, segs.size
        assert_equal "Hello everyone", segs.first.text
      end

      test "segments_for_speaker returns empty for unknown" do
        reader = JsonlReader.new(fixture_path("transcription/sample_transcript.jsonl"))
        assert_empty reader.segments_for_speaker("Unknown")
      end

      test "segment with nil speaker is not considered unidentified" do
        reader = build_reader_from_lines(
          '{"type":"metadata","recorded_at":"now"}',
          '{"speaker":null,"text":"background noise","start_time":0,"end_time":1,"channel":0}'
        )
        assert_not reader.unidentified_speakers?
        assert_empty reader.unidentified_speakers
      end

      test "unidentified_speakers? returns false when all identified" do
        reader = build_reader_from_lines(
          '{"type":"metadata","recorded_at":"now"}',
          '{"speaker":"Alice","text":"hi","start_time":0,"end_time":1,"channel":0}'
        )
        assert_not reader.unidentified_speakers?
      end

      test "unidentified_speakers? recognizes channel-prefixed labels" do
        reader = build_reader_from_lines(
          '{"type":"metadata","recorded_at":"now"}',
          '{"speaker":"Ch0 Speaker 0","text":"hello","start_time":0,"end_time":1,"channel":0}',
          '{"speaker":"Ch1 Speaker 0","text":"hi there","start_time":1,"end_time":2,"channel":1}'
        )
        assert reader.unidentified_speakers?
        labels = reader.unidentified_speakers
        assert_includes labels, "Ch0 Speaker 0"
        assert_not_includes labels, "Ch1 Speaker 0"
      end

      test "unidentified_speakers? returns false when only Ch1 speakers unidentified" do
        reader = build_reader_from_lines(
          '{"type":"metadata","recorded_at":"now"}',
          '{"speaker":"Ch1 Speaker 0","text":"mic audio","start_time":0,"end_time":2,"channel":1}',
          '{"speaker":"Alice","text":"identified","start_time":2,"end_time":4,"channel":0}'
        )
        assert_not reader.unidentified_speakers?
      end

      test "Ch1 speakers excluded from unidentified_speakers" do
        reader = build_reader_from_lines(
          '{"type":"metadata","recorded_at":"now"}',
          '{"speaker":"Ch1 Speaker 0","text":"my mic audio","start_time":0,"end_time":2,"channel":1}',
          '{"speaker":"Ch1 Speaker 1","text":"more mic audio","start_time":2,"end_time":4,"channel":1}',
          '{"speaker":"Ch0 Speaker 0","text":"remote speaker","start_time":1,"end_time":3,"channel":0}'
        )
        labels = reader.unidentified_speakers
        assert_includes labels, "Ch0 Speaker 0"
        assert_not_includes labels, "Ch1 Speaker 0"
        assert_not_includes labels, "Ch1 Speaker 1"
      end

      test "Ch1 speakers still present in segments" do
        reader = build_reader_from_lines(
          '{"type":"metadata","recorded_at":"now"}',
          '{"speaker":"Ch1 Speaker 0","text":"my mic audio","start_time":0,"end_time":2,"channel":1}',
          '{"speaker":"Ch0 Speaker 0","text":"remote speaker","start_time":1,"end_time":3,"channel":0}'
        )
        speakers = reader.segments.map(&:speaker)
        assert_includes speakers, "Ch1 Speaker 0"
        assert_includes speakers, "Ch0 Speaker 0"
      end

      private

      def build_reader_from_lines(*lines)
        Dir.mktmpdir do |tmp|
          path = File.join(tmp, "test.jsonl")
          File.write(path, "#{lines.join("\n")}\n")
          JsonlReader.new(path)
        end
      end
    end
  end
end
