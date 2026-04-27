# frozen_string_literal: true

require "test_helper"
require "stringio"

module EarlScribe
  module Cli
    class TerminalDisplayTest < Minitest::Test
      setup do
        @output = StringIO.new
        @display = TerminalDisplay.new(output: @output)
      end

      test "commit prints segment line to output" do
        seg = build_seg(speaker: "Speaker 0", text: "Hello")
        @display.commit(seg, cache_key: "0")
        assert_includes @output.string, "Speaker 0: Hello"
      end

      test "commit tracks the line for later reprinting" do
        seg = build_seg(speaker: "Speaker 0", text: "Hello")
        @display.commit(seg, cache_key: "0")
        lines = @display.instance_variable_get(:@lines)
        assert_equal 1, lines.size
        assert_includes lines.first.text, "Speaker 0: Hello"
      end

      test "print_line tracks text internally" do
        @display.print_line("Hello world")
        lines = @display.instance_variable_get(:@lines)
        assert_equal 1, lines.size
        assert_equal "Hello world", lines.first.text
      end

      test "print_line with nil cache_key works" do
        @display.print_line("No speaker line")
        lines = @display.instance_variable_get(:@lines)
        assert_equal "No speaker line", lines.last.text
        assert_empty lines.last.cache_keys
      end

      test "reprint_speaker skips ANSI on non-TTY output" do
        @display.print_line("[00:00:00] Speaker 0: Hello", cache_key: "0")
        @output.string = ""

        @display.reprint_speaker("0", "Speaker 0", "Alice")

        assert_empty @output.string
      end

      test "reprint_speaker updates internal tracked lines even without TTY" do
        @display.print_line("[00:00:00] Speaker 0: Hello", cache_key: "0")
        @display.reprint_speaker("0", "Speaker 0", "Alice")

        lines = @display.instance_variable_get(:@lines)
        assert_equal "[00:00:00] Alice: Hello", lines.last.text
      end

      test "reprint_speaker emits ANSI codes on TTY" do
        tty_output = StringIO.new
        tty_output.define_singleton_method(:tty?) { true }
        display = TerminalDisplay.new(output: tty_output)

        display.print_line("[00:00:00] Speaker 0: Hello", cache_key: "0")
        tty_output.truncate(0)
        tty_output.rewind

        display.reprint_speaker("0", "Speaker 0", "Alice")

        ansi = tty_output.string
        assert_includes ansi, "\e["
        assert_includes ansi, "[00:00:00] Alice: Hello"
      end

      test "reprint_speaker only updates matching cache_key" do
        tty_output = StringIO.new
        tty_output.define_singleton_method(:tty?) { true }
        display = TerminalDisplay.new(output: tty_output)

        display.print_line("[00:00:00] Speaker 0: Hello", cache_key: "0")
        display.print_line("[00:00:01] Speaker 1: World", cache_key: "1")
        tty_output.truncate(0)
        tty_output.rewind

        display.reprint_speaker("0", "Speaker 0", "Alice")

        lines = display.instance_variable_get(:@lines)
        assert_equal "[00:00:00] Alice: Hello", lines[0].text
        assert_equal "[00:00:01] Speaker 1: World", lines[1].text
      end

      test "reprint_speaker handles no matching lines gracefully" do
        @display.print_line("[00:00:00] Speaker 0: Hello", cache_key: "0")
        @display.reprint_speaker("99", "Speaker 99", "Bob")

        lines = @display.instance_variable_get(:@lines)
        assert_equal "[00:00:00] Speaker 0: Hello", lines.last.text
      end

      test "reprint_speaker skips lines with nil cache_keys" do
        @display.print_line("No speaker line")
        @display.reprint_speaker("0", "Speaker 0", "Alice")

        lines = @display.instance_variable_get(:@lines)
        assert_equal "No speaker line", lines.last.text
      end

      test "reprint_speaker rewrites a previously committed line" do
        seg = build_seg(speaker: "Speaker 0", text: "Hello")
        @display.commit(seg, cache_key: "0")

        @display.reprint_speaker("0", "Speaker 0", "Alice")
        lines = @display.instance_variable_get(:@lines)
        assert_includes lines.first.text, "Alice"
      end

      test "reprint_speaker updates multiple lines with same cache_key" do
        tty_output = StringIO.new
        tty_output.define_singleton_method(:tty?) { true }
        display = TerminalDisplay.new(output: tty_output)

        display.print_line("[00:00:00] Speaker 0: Hello", cache_key: "0")
        display.print_line("[00:00:05] Speaker 0: More text", cache_key: "0")
        tty_output.truncate(0)
        tty_output.rewind

        display.reprint_speaker("0", "Speaker 0", "Alice")

        lines = display.instance_variable_get(:@lines)
        assert_equal "[00:00:00] Alice: Hello", lines[0].text
        assert_equal "[00:00:05] Alice: More text", lines[1].text
      end

      test "trim_lines keeps at most MAX_TRACKED_LINES" do
        (TerminalDisplay::MAX_TRACKED_LINES + 10).times do |i|
          @display.print_line("Line #{i}", cache_key: i.to_s)
        end

        lines = @display.instance_variable_get(:@lines)
        assert_equal TerminalDisplay::MAX_TRACKED_LINES, lines.size
      end

      private

      def build_seg(speaker: nil, text: "test", start_time: 0.0, end_time: 1.0, channel: 0)
        Transcription::Result.new(speaker: speaker, text: text, start_time: start_time,
                                  end_time: end_time, channel: channel)
      end
    end
  end
end
