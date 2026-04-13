# frozen_string_literal: true

require "mutex_m"
require "set"

module EarlScribe
  module Cli
    # Thread-safe terminal output with ANSI-based line reprinting for speaker corrections.
    # Supports line accumulation: segments from the same speaker are concatenated into one line.
    class TerminalDisplay
      include Mutex_m

      MAX_TRACKED_LINES = 200

      # A previously displayed line with its associated speaker cache keys
      TrackedLine = Struct.new(:text, :cache_keys, keyword_init: true) do
        def matches?(cache_key, name)
          cache_keys.include?(cache_key) && text.include?(name)
        end
      end

      def initialize(output: nil)
        super()
        @output = output
        @lines = []
        @pending = nil
      end

      # Accumulates segments by speaker. Returns a flushed Result when the speaker changes, nil otherwise.
      def accumulate(seg, cache_key:)
        synchronize do
          same_speaker = @pending && @pending[:speaker] == seg.speaker
          same_speaker ? append_segment(seg, cache_key) : start_segment(seg, cache_key)
        end
      end

      # Finalizes and returns the pending line (call on interrupt/shutdown).
      def flush
        synchronize { finalize_pending }
      end

      def print_line(text, cache_key: nil)
        synchronize do
          keys = cache_key ? Set[cache_key] : Set.new
          @lines << TrackedLine.new(text: text.dup, cache_keys: keys)
          trim_lines
        end
      end

      def reprint_speaker(cache_key, old_name, new_name)
        synchronize do
          if @pending && @pending[:cache_keys]&.include?(cache_key)
            @pending[:speaker] = @pending[:speaker]&.gsub(old_name, new_name)
          end
          indices = matching_indices(cache_key, old_name)
          return if indices.empty?

          rewrite_lines(indices, old_name, new_name) if tty?
          update_tracked_lines(cache_key, old_name, new_name)
        end
      end

      private

      def append_segment(seg, cache_key)
        @pending[:text] << " " << seg.text
        @pending[:end_time] = seg.end_time
        @pending[:cache_keys] << cache_key
        output.print(" #{seg.text}")
        output.flush
        nil
      end

      def start_segment(seg, cache_key)
        flushed = finalize_pending
        @pending = { speaker: seg.speaker, text: seg.text.dup, start_time: seg.start_time,
                     end_time: seg.end_time, channel: seg.channel, cache_keys: Set[cache_key] }
        output.print(build_result.to_timestamped_s)
        output.flush
        flushed
      end

      def finalize_pending
        return nil unless @pending

        result = build_result
        output.puts
        @lines << TrackedLine.new(text: result.to_timestamped_s.dup, cache_keys: @pending[:cache_keys])
        trim_lines
        @pending = nil
        result
      end

      def build_result
        Transcription::Result.new(speaker: @pending[:speaker], text: @pending[:text],
                                  start_time: @pending[:start_time], end_time: @pending[:end_time],
                                  channel: @pending[:channel])
      end

      def matching_indices(cache_key, old_name)
        @lines.each_with_index.filter_map { |line, idx| idx if line.matches?(cache_key, old_name) }
      end

      def rewrite_lines(indices, old_name, new_name)
        out = output
        out.write("\e[s")
        total = @lines.size
        indices.reverse_each do |idx|
          lines_up = total - idx
          out.write("\e[#{lines_up}A\r\e[2K")
          out.write(@lines[idx].text.gsub(old_name, new_name))
        end
        out.write("\e[u")
        out.flush
      end

      def update_tracked_lines(cache_key, old_name, new_name)
        matching_lines(cache_key).each { |tracked| tracked.text.gsub!(old_name, new_name) }
      end

      def matching_lines(cache_key)
        @lines.select { |tracked| tracked.cache_keys.include?(cache_key) }
      end

      def trim_lines
        @lines.shift(@lines.size - MAX_TRACKED_LINES) if @lines.size > MAX_TRACKED_LINES
      end

      def output
        @output || $stdout
      end

      def tty?
        output.respond_to?(:tty?) && output.tty?
      end
    end
  end
end
