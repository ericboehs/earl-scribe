# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Immutable transcript segment with speaker, text, timing, and channel info
    Result = Struct.new(:speaker, :text, :start_time, :end_time, :channel, :original_speaker, :cache_key,
                        keyword_init: true) do
      def to_s
        speaker ? "#{speaker}: #{text}" : text
      end

      def to_timestamped_s
        "[#{format_timestamp}] #{self}"
      end

      def to_h
        result = { speaker: speaker, text: text, start_time: start_time, end_time: end_time, channel: channel }
        result[:original_speaker] = original_speaker if original_speaker
        result[:cache_key] = cache_key if cache_key
        result
      end

      def duration
        return 0 unless start_time && end_time

        end_time - start_time
      end

      private

      def format_timestamp
        seconds = (start_time || 0).to_i
        format("%<h>02d:%<m>02d:%<s>02d", h: seconds / 3600, m: (seconds % 3600) / 60, s: seconds % 60)
      end
    end
  end
end
