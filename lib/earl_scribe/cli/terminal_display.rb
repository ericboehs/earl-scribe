# frozen_string_literal: true

require "mutex_m"
require "set"
require_relative "tracked_line"

module EarlScribe
  module Cli
    class TerminalDisplay
      include Mutex_m

      MAX_TRACKED_LINES = 200

      def initialize(output: nil)
        super()
        @output = output
        @lines = []
      end

      def commit(seg, cache_key:)
        synchronize do
          line_text = seg.to_timestamped_s
          output.puts(line_text)
          output.flush
          @lines << TrackedLine.new(text: line_text.dup, cache_keys: Set[cache_key])
          trim_lines
        end
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
          indices = matching_indices(cache_key, old_name)
          return if indices.empty?

          rewrite_lines(indices, old_name, new_name) if tty?
          update_tracked_lines(cache_key, old_name, new_name)
        end
      end

      private

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
