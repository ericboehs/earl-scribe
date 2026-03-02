# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Filters common whisper.cpp false positives like "[BLANK_AUDIO]" and repeated fillers
    module HallucinationFilter
      PATTERNS = [
        /\A\[BLANK_AUDIO\]\z/i,
        /\A(You[. ]*)+\z/i,
        /\A(Thank you[. ]*)+\z/i,
        /\A(Thanks for watching[.!]*\s*)+\z/i,
        /\A(Bye[. ]*)+\z/i,
        /\A(Okay[. ]*)+\z/i,
        /\A(Oh[. ]*)+\z/i,
        /\A(So[. ]*)+\z/i,
        /\A(\.+\s*)+\z/,
        /\A[.!, ]+\z/
      ].freeze

      def self.hallucination?(text)
        stripped = text.to_s.strip
        return true if stripped.empty?

        PATTERNS.any? { |pattern| stripped.match?(pattern) }
      end

      def self.filter(text)
        return nil if hallucination?(text)

        text.strip
      end
    end
  end
end
