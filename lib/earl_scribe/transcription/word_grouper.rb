# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Groups consecutive words by speaker into labeled Result segments
    module WordGrouper
      # Accumulates words for a single speaker segment
      Segment = Struct.new(:speaker_id, :words, keyword_init: true)

      def self.group(words, speaker_prefix: nil)
        return [] unless words&.any?

        build_segments(words).map { |seg| to_result(seg, speaker_prefix) }
      end

      def self.build_segments(words)
        words.each_with_object([]) do |word, segments|
          speaker, text = extract_word_info(word)
          current = segments.last

          if current&.speaker_id == speaker
            current.words << text
          else
            segments << Segment.new(speaker_id: speaker, words: [text])
          end
        end
      end

      def self.extract_word_info(word)
        [word["speaker"] || 0, word["punctuated_word"] || word["word"] || ""]
      end

      def self.to_result(segment, prefix)
        speaker_id = segment.speaker_id
        label = prefix ? "#{prefix} Speaker #{speaker_id}" : "Speaker #{speaker_id}"
        Result.new(speaker: label, text: segment.words.join(" "))
      end

      private_class_method :build_segments, :extract_word_info, :to_result
    end
  end
end
