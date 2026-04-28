# frozen_string_literal: true

require "monitor"
require "tempfile"
require "timeout"

module EarlScribe
  module Summarizer
    # Drives the rolling re-summary timer plus the SIGUSR1 trap, coalescing
    # overlapping triggers and atomically rewriting the summary file.
    class Scheduler
      include MonitorMixin

      MAX_CONSECUTIVE_FAILURES = 3

      def initialize(transcript_source:, summarizer:, output_path:, **opts)
        super()
        store_dependencies(transcript_source, summarizer, output_path, opts)
        @running = false
        @thread = nil
        @trigger_queue = Thread::Queue.new
        @next_run_at = nil
        @consecutive_failures = 0
      end

      def store_dependencies(transcript_source, summarizer, output_path, opts)
        @transcript_source = transcript_source
        @summarizer = summarizer
        @output_path = output_path
        @interval_sec = opts.fetch(:interval_sec, 180)
        @clock = opts.fetch(:clock, -> { Time.now })
        @trap_signal = opts.fetch(:trap_signal, true)
      end

      def start
        return if @running

        @running = true
        install_trap if @trap_signal
        @next_run_at = @clock.call + @interval_sec
        @thread = Thread.new { run_loop }
      end

      def stop
        return unless @running

        @running = false
        uninstall_trap if @trap_signal
        @trigger_queue << :stop
        @thread&.join(@interval_sec + 5)
        @thread = nil
      end

      def trigger
        @trigger_queue << :now
      end

      def run_once
        synchronize do
          transcript = @transcript_source.call
          return if transcript.to_s.strip.empty?

          summary = @summarizer.call(transcript)
          write_atomic(summary)
        end
      end

      private

      def run_loop
        while @running
          wait = next_wait
          msg = wait.positive? ? pop_with_timeout(wait) : :timeout
          break if msg == :stop

          safe_run_once
          @next_run_at = @clock.call + @interval_sec
        end
      end

      def safe_run_once
        run_once
        @consecutive_failures = 0
      rescue StandardError => error
        record_failure(error)
      end

      def record_failure(error)
        @consecutive_failures += 1
        EarlScribe.logger.error(
          "summarizer error (#{@consecutive_failures}/#{MAX_CONSECUTIVE_FAILURES}): " \
          "#{error.class}: #{error.message}\n#{(error.backtrace || []).first(5).join("\n")}"
        )
        return if @consecutive_failures < MAX_CONSECUTIVE_FAILURES

        warn "earl-scribe: disabling rolling summarizer after #{@consecutive_failures} consecutive failures"
        @running = false
      end

      def next_wait
        @next_run_at - @clock.call
      end

      def pop_with_timeout(seconds)
        Timeout.timeout(seconds) { @trigger_queue.pop }
      rescue Timeout::Error
        :timeout
      end

      def install_trap
        @prev_trap = Signal.trap("USR1") { @trigger_queue << :now }
      end

      def uninstall_trap
        Signal.trap("USR1", @prev_trap || "DEFAULT")
      end

      def write_atomic(content)
        require "fileutils"
        tmp = Tempfile.create(["summary", ".md"], File.dirname(@output_path))
        flush_and_rename(tmp, content)
      rescue StandardError
        FileUtils.rm_f(tmp.path) if tmp
        raise
      end

      def flush_and_rename(tmp, content)
        tmp.write(content)
        tmp.flush
        tmp.fsync
        tmp.close
        File.rename(tmp.path, @output_path)
      end
    end
  end
end
