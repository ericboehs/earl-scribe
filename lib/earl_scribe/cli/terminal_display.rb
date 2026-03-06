# frozen_string_literal: true

require "mutex_m"

module EarlScribe
  module Cli
    # Thread-safe terminal output with ANSI-based line reprinting for speaker corrections.
    # Supports line accumulation: segments from the same speaker are concatenated into one line.
    class TerminalDisplay
      include Mutex_m

      MAX_TRACKED_LINES = 200

      TrackedLine = Struct.new(:text, :cache_key, keyword_init: true)

      def initialize(output: nil)
        super()
        @output = output
        @lines = []
        @pending = nil
      end

      # Accumulates segments by speaker. Returns a flushed Result when the speaker changes, nil otherwise.
      def accumulate(seg, cache_key:)
        synchronize do
          same = @pending && @pending[:cache_key] == cache_key && @pending[:speaker] == seg.speaker
          same ? append_segment(seg) : start_segment(seg, cache_key)
        end
      end

      # Finalizes and returns the pending line (call on interrupt/shutdown).
      def flush
        synchronize { finalize_pending }
      end

      def print_line(text, cache_key: nil)
        synchronize do
          @lines << TrackedLine.new(text: text, cache_key: cache_key)
          trim_lines
        end
      end

      def reprint_speaker(cache_key, old_name, new_name)
        synchronize do
          if @pending && @pending[:cache_key] == cache_key
            @pending[:speaker] = @pending[:speaker]&.gsub(old_name, new_name)
          end
          indices = matching_indices(cache_key, old_name)
          return if indices.empty?

          rewrite_lines(indices, old_name, new_name) if tty?
          update_tracked_lines(cache_key, old_name, new_name)
        end
      end

      private

      def append_segment(seg)
        @pending[:text] << " " << seg.text
        @pending[:end_time] = seg.end_time
        output.print(" #{seg.text}")
        output.flush
        nil
      end

      def start_segment(seg, cache_key)
        flushed = finalize_pending
        @pending = { speaker: seg.speaker, text: seg.text.dup, start_time: seg.start_time,
                     end_time: seg.end_time, channel: seg.channel, cache_key: cache_key }
        output.print(build_result.to_timestamped_s)
        output.flush
        flushed
      end

      def finalize_pending
        return nil unless @pending

        result = build_result
        output.puts
        @lines << TrackedLine.new(text: result.to_timestamped_s, cache_key: @pending[:cache_key])
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
        @lines.each_with_index.filter_map do |tracked, idx|
          idx if tracked.cache_key == cache_key && tracked.text.include?(old_name)
        end
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
        @lines.each do |tracked|
          next unless tracked.cache_key == cache_key

          tracked.text = tracked.text.gsub(old_name, new_name)
        end
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
