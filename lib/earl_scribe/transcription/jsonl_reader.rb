# frozen_string_literal: true

require "json"

module EarlScribe
  module Transcription
    # Reads JSONL transcript files into metadata and Result segments for the learn command
    class JsonlReader
      attr_reader :metadata, :segments

      def initialize(path)
        @metadata = {}
        @segments = []
        parse(path)
      end

      def meeting_title
        metadata["meeting_title"]
      end

      def recorded_at
        metadata["recorded_at"]
      end

      def unidentified_speakers?
        segments.any? { |seg| unidentified?(seg.speaker) && !ch1_speaker?(seg.speaker) }
      end

      def unidentified_speakers
        segments.select { |seg| unidentified?(seg.speaker) && !ch1_speaker?(seg.speaker) }
                .map(&:speaker)
                .uniq
      end

      def segments_for_speaker(label)
        segments.select { |seg| seg.speaker == label }
      end

      private

      def parse(path)
        File.foreach(path) do |line|
          data = JSON.parse(line)
          if data["type"] == "metadata"
            @metadata = data
          else
            @segments << build_result(data)
          end
        end
      end

      def build_result(data)
        Result.new(
          speaker: data["speaker"],
          text: data["text"],
          start_time: data["start_time"],
          end_time: data["end_time"],
          channel: data["channel"]
        )
      end

      def unidentified?(speaker)
        speaker&.match?(/\A(Ch\d+ )?Speaker \d+\z/)
      end

      def ch1_speaker?(speaker)
        speaker.start_with?("Ch1 ")
      end
    end
  end
end
