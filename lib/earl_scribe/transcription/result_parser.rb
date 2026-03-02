# frozen_string_literal: true

require "json"

module EarlScribe
  module Transcription
    # Parses Deepgram JSON responses into structured results
    module ResultParser
      def self.parse(json_string)
        data = JSON.parse(json_string)
        return nil unless data["type"] == "Results" && data["is_final"]

        extract_alternative(data)
      end

      def self.extract_alternative(data)
        alt = data.dig("channel", "alternatives", 0)
        transcript = alt&.dig("transcript").to_s.strip
        return nil if transcript.empty?

        { channel_index: data.dig("channel_index", 0) || 0, transcript: transcript, words: alt.fetch("words", []) }
      end

      private_class_method :extract_alternative
    end
  end
end
