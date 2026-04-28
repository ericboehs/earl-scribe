# frozen_string_literal: true

require "test_helper"
require "stringio"
require "earl_scribe/cli/rerun_progress"

module EarlScribe
  module Cli
    class RerunProgressTest < Minitest::Test
      def with_stub_stderr
        stubbed_stderr = StringIO.new
        original = $stderr
        $stderr = stubbed_stderr
        # Stub tty? to return true so paint actually emits
        RerunProgress.singleton_class.send(:alias_method, :__tty?, :tty?)
        RerunProgress.define_singleton_method(:tty?) { true }
        yield stubbed_stderr
      ensure
        $stderr = original
        RerunProgress.singleton_class.send(:alias_method, :tty?, :__tty?)
      end

      def test_paint_does_nothing_when_audio_sec_nil
        with_stub_stderr do |io|
          RerunProgress.paint(nil, duration: 10, last_paint: 0.0)
          assert_empty io.string
        end
      end

      def test_paint_does_nothing_when_duration_zero
        with_stub_stderr do |io|
          RerunProgress.paint(5.0, { duration: 0, last_paint: 0.0 })
          assert_empty io.string
        end
      end

      def test_paint_does_nothing_when_progress_under_0_5_seconds
        ctx = { duration: 10.0, last_paint: 5.0 }
        with_stub_stderr do |io|
          RerunProgress.paint(5.2, ctx)
          assert_empty io.string
        end
      end

      def test_paint_emits_bar_when_progressing
        ctx = { duration: 10.0, last_paint: 0.0 }
        with_stub_stderr do |io|
          RerunProgress.paint(5.0, ctx)
          assert_includes io.string, "rerun ["
          assert_includes io.string, "50.0%"
          assert_in_delta 5.0, ctx[:last_paint], 1e-6
        end
      end

      def test_paint_clamps_pct_at_max
        ctx = { duration: 10.0, last_paint: 0.0 }
        with_stub_stderr do |io|
          RerunProgress.paint(15.0, ctx)
          assert_includes io.string, "100.0%"
        end
      end

      def test_clear_emits_when_tty
        with_stub_stderr do |io|
          RerunProgress.clear
          assert_includes io.string, "\r\e[K"
        end
      end

      def test_clear_silent_when_not_tty
        original = $stderr
        $stderr = StringIO.new
        RerunProgress.clear
        assert_empty $stderr.string
      ensure
        $stderr = original
      end

      def test_start_spinner_returns_nil_without_tty
        assert_nil RerunProgress.start_spinner
      end
    end
  end
end
