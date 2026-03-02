# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Immutable transcript segment with speaker, text, timing, and channel info
    Result = Struct.new(:speaker, :text, :start_time, :end_time, :channel, keyword_init: true) do
      def to_s
        speaker ? "#{speaker}: #{text}" : text
      end

      def duration
        return 0 unless start_time && end_time

        end_time - start_time
      end
    end
  end
end
