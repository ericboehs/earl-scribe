# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Summarizer
    class SchedulerTest < Minitest::Test
      setup do
        @dir = Dir.mktmpdir("earl-scheduler")
        @output = File.join(@dir, "summary.md")
      end

      teardown do
        FileUtils.rm_rf(@dir)
      end

      test "run_once skips when transcript is blank" do
        called = false
        summarizer = build_summarizer do |_|
          called = true
          "x"
        end
        scheduler = build_scheduler(summarizer: summarizer, transcript: "")
        scheduler.run_once
        assert_not called
        assert_not File.exist?(@output)
      end

      test "run_once writes summary atomically" do
        summarizer = build_summarizer { |t| "summary of: #{t.strip}" }
        scheduler = build_scheduler(summarizer: summarizer, transcript: "hello world")
        scheduler.run_once
        assert_equal "summary of: hello world", File.read(@output)
        # tmp file should be gone after rename
        assert_empty Dir.glob("#{@output}.tmp")
      end

      test "trigger fires an immediate run via background thread" do
        runs = []
        summarizer = build_summarizer do |t|
          runs << t
          "s"
        end
        scheduler = build_scheduler(summarizer: summarizer, transcript: "live", interval: 60,
                                    trap_signal: false)
        scheduler.start
        scheduler.trigger
        Thread.pass until runs.any? || !scheduler.instance_variable_get(:@running)
        scheduler.stop
        assert runs.any?, "expected the trigger to fire at least once"
      end

      test "stop is idempotent" do
        scheduler = build_scheduler(summarizer: build_summarizer { |_| "" }, transcript: "x")
        scheduler.stop # before start
        scheduler.start
        scheduler.stop
        scheduler.stop # second stop a no-op
      end

      test "summarizer error is caught and logged" do
        errored = []
        logger = Logger.new(StringIO.new)
        logger.define_singleton_method(:error) { |msg| errored << msg }

        summarizer = build_summarizer { |_| raise "boom" }
        scheduler = build_scheduler(summarizer: summarizer, transcript: "x", interval: 60,
                                    trap_signal: false)

        EarlScribe.stub(:logger, logger) do
          scheduler.start
          scheduler.trigger
          Thread.pass until errored.any? || !scheduler.instance_variable_get(:@running)
          scheduler.stop
        end
        assert(errored.any? { |m| m.include?("boom") })
      end

      test "scheduler disables itself after MAX_CONSECUTIVE_FAILURES failures" do
        runs = 0
        summarizer = build_summarizer do |_|
          runs += 1
          raise "boom"
        end
        scheduler = build_scheduler(summarizer: summarizer, transcript: "x", interval: 60,
                                    trap_signal: false)
        EarlScribe.stub(:logger, Logger.new(StringIO.new)) do
          capture_io do
            scheduler.start
            Scheduler::MAX_CONSECUTIVE_FAILURES.times { scheduler.trigger }
            Thread.pass until runs >= Scheduler::MAX_CONSECUTIVE_FAILURES
            Thread.pass while scheduler.instance_variable_get(:@running)
            scheduler.stop
          end
        end
        assert_equal Scheduler::MAX_CONSECUTIVE_FAILURES, runs
        assert_not scheduler.instance_variable_get(:@running)
      end

      test "consecutive_failures resets after a successful run" do
        calls = 0
        summarizer = build_summarizer do |_|
          calls += 1
          raise "boom" if calls == 1

          "ok"
        end
        scheduler = build_scheduler(summarizer: summarizer, transcript: "x", interval: 60,
                                    trap_signal: false)
        EarlScribe.stub(:logger, Logger.new(StringIO.new)) do
          scheduler.start
          scheduler.trigger
          Thread.pass until calls >= 1
          scheduler.trigger
          Thread.pass until calls >= 2
          scheduler.stop
        end
        assert_equal 0, scheduler.instance_variable_get(:@consecutive_failures)
      end

      test "start is idempotent when already running" do
        scheduler = build_scheduler(summarizer: build_summarizer { |_| "" }, transcript: "x")
        scheduler.start
        thread = scheduler.instance_variable_get(:@thread)
        scheduler.start # second call should be a no-op
        assert_same thread, scheduler.instance_variable_get(:@thread)
        scheduler.stop
      end

      test "overdue runs fire immediately without waiting" do
        runs = []
        clock_value = Time.at(0)
        clock = -> { clock_value }
        summarizer = build_summarizer do |t|
          runs << t
          "x"
        end
        scheduler = Scheduler.new(
          transcript_source: -> { "transcript" },
          summarizer: summarizer,
          output_path: @output,
          interval_sec: 60,
          clock: clock,
          trap_signal: false
        )
        scheduler.start
        # Advance clock past next_run_at so wait <= 0 → :timeout branch
        clock_value = Time.at(120)
        Thread.pass until runs.any? || !scheduler.instance_variable_get(:@running)
        scheduler.stop
        assert runs.any?
      end

      test "write_atomic cleans up temp file when rename fails" do
        summarizer = build_summarizer { |_| "summary text" }
        scheduler = build_scheduler(summarizer: summarizer, transcript: "x")
        File.stub(:rename, ->(*) { raise Errno::EACCES }) do
          assert_raises(Errno::EACCES) { scheduler.run_once }
        end
        leftovers = Dir.glob(File.join(@dir, "summary-*.md"))
        assert_empty leftovers, "tmp file leaked: #{leftovers.inspect}"
      end

      test "trigger pushes :now via SIGUSR1 when trap is installed" do
        runs = []
        prev = Signal.trap("USR1", "DEFAULT")
        scheduler = build_scheduler(summarizer: build_summarizer do |t|
          runs << t
          "ok"
        end,
                                    transcript: "live", interval: 60, trap_signal: true)
        scheduler.start
        Process.kill("USR1", Process.pid)
        Thread.pass until runs.any?
        scheduler.stop
        Signal.trap("USR1", prev)
        assert runs.any?
      end

      test "install_trap restores prior handler on stop" do
        prev = Signal.trap("USR1", "DEFAULT")
        scheduler = build_scheduler(summarizer: build_summarizer { |_| "" }, transcript: "x",
                                    trap_signal: true)
        scheduler.start
        scheduler.stop
        assert_equal "DEFAULT", Signal.trap("USR1", prev)
      end

      private

      def build_summarizer(&block)
        s = Object.new
        s.define_singleton_method(:call, &block)
        s
      end

      def build_scheduler(summarizer:, transcript:, interval: 60, trap_signal: false)
        Scheduler.new(
          transcript_source: -> { transcript },
          summarizer: summarizer,
          output_path: @output,
          interval_sec: interval,
          trap_signal: trap_signal
        )
      end
    end
  end
end
