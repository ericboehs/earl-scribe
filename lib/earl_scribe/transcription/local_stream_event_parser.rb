# frozen_string_literal: true

require "json"

module EarlScribe
  module Transcription
    class LocalStreamEventParser
      def initialize
        @last_audio_sec = 0.0
        @leftover = +""
        @accumulated = +""
      end

      def feed(bytes)
        @leftover << bytes
        events = []
        while (newline = @leftover.index("\n"))
          line = @leftover.slice!(0..newline).chomp
          parsed = parse_line(line)
          events << parsed if parsed
        end
        events
      end

      def parse_line(line)
        return nil if line.empty?

        data = JSON.parse(line)
        build_event(data["type"], data)
      rescue JSON::ParserError
        { event: :malformed, data: { "line" => line } }
      end

      def build_event(kind, data)
        event = { event: kind.to_sym, data: data }
        case kind
        when "eou" then event[:result] = build_eou_result(data)
        when "final" then event[:result] = build_tail_result(data)
        end
        event
      end

      private

      def build_eou_result(data)
        text = data["text"].to_s.strip
        return nil if text.empty?

        end_time = (data["audio_sec"] || @last_audio_sec).to_f
        record_segment(text, end_time)
      end

      def build_tail_result(data)
        full_text = data["text"].to_s.strip
        tail = compute_tail(full_text)
        return nil if tail.empty?

        end_time = (data["audio_duration_sec"] || @last_audio_sec).to_f
        record_segment(tail, end_time)
      end

      def record_segment(text, end_time)
        start_time = @last_audio_sec
        @last_audio_sec = end_time
        @accumulated = @accumulated.empty? ? text.dup : "#{@accumulated} #{text}"
        word = { "speaker" => 0, "punctuated_word" => text, "word" => text,
                 "start" => start_time, "end" => end_time }
        { channel_index: 0, transcript: text, words: [word] }
      end

      def compute_tail(full_text)
        return full_text if @accumulated.empty?

        full_text.start_with?(@accumulated) ? full_text[@accumulated.length..].to_s.strip : full_text
      end
    end
  end
end
