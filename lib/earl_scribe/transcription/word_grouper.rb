# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Groups consecutive words by speaker into labeled Result segments
    module WordGrouper
      # Accumulates words for a single speaker segment
      Segment = Struct.new(:speaker_id, :words, :raw_words, keyword_init: true)

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
            current.raw_words << word
          else
            segments << Segment.new(speaker_id: speaker, words: [text], raw_words: [word])
          end
        end
      end

      def self.extract_word_info(word)
        speaker = word["channel_hint"] == "mic" ? :me : (word["speaker"] || 0)
        [speaker, word["punctuated_word"] || word["word"] || ""]
      end

      def self.to_result(segment, prefix)
        raw = segment.raw_words
        Result.new(speaker: speaker_label(segment.speaker_id, prefix),
                   text: segment.words.join(" "),
                   start_time: raw.first["start"], end_time: raw.last["end"])
      end

      def self.speaker_label(speaker_id, prefix)
        return ENV["EARL_SCRIBE_ME_NAME"] || "Me" if speaker_id == :me

        prefix ? "#{prefix} Speaker #{speaker_id}" : "Speaker #{speaker_id}"
      end

      private_class_method :build_segments, :extract_word_info, :to_result, :speaker_label
    end
  end
end
