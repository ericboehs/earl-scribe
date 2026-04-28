# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Transcription
    class LocalStreamLifecycleTest < Minitest::Test
      def test_spawn_error_reason_recognized_errors
        assert_equal "not found", LocalStreamLifecycle.spawn_error_reason(Errno::ENOENT.new)
        assert_equal "is not executable", LocalStreamLifecycle.spawn_error_reason(Errno::EACCES.new)
        assert_equal "is the wrong architecture", LocalStreamLifecycle.spawn_error_reason(Errno::ENOEXEC.new)
      end

      def test_spawn_error_reason_unknown_class_falls_back_to_generic
        assert_equal "could not be spawned", LocalStreamLifecycle.spawn_error_reason(StandardError.new)
      end

      def test_signal_subprocess_no_op_when_wait_thr_nil
        # Should not raise
        LocalStreamLifecycle.signal_subprocess(nil, :INT)
      end

      def test_signal_subprocess_swallows_esrch
        wait_thr = Object.new
        wait_thr.define_singleton_method(:pid) { 999_999 }
        Process.stub(:kill, ->(_sig, _pid) { raise Errno::ESRCH }) do
          LocalStreamLifecycle.signal_subprocess(wait_thr, :INT)
        end
      end

      def test_warn_if_reader_hung_silent_when_not_hung
        captured = capture_logger(:warn) do
          LocalStreamLifecycle.warn_if_reader_hung(false, 30)
        end
        assert_empty captured
      end

      def test_warn_if_reader_hung_logs_when_hung
        captured = capture_logger(:warn) do
          LocalStreamLifecycle.warn_if_reader_hung(true, 30)
        end
        assert_includes captured.first, "30s"
      end

      def test_check_exit_status_silent_on_nil_thread
        # Should not raise
        LocalStreamLifecycle.check_exit_status(nil)
      end

      def test_check_exit_status_silent_on_success
        wait_thr = build_wait_thr(success: true)
        LocalStreamLifecycle.check_exit_status(wait_thr)
      end

      def test_check_exit_status_logs_failure_with_exitstatus
        captured = capture_logger(:error) do
          LocalStreamLifecycle.check_exit_status(build_wait_thr(success: false, exitstatus: 7))
        end
        assert_includes captured.first, "exited 7"
      end

      def test_check_exit_status_logs_failure_via_signal
        captured = capture_logger(:error) do
          LocalStreamLifecycle.check_exit_status(build_wait_thr(success: false, exitstatus: nil, termsig: 9))
        end
        assert_includes captured.first, "via signal 9"
      end

      def test_log_subprocess_dead_logs_at_error_level
        captured = capture_logger(:error) { LocalStreamLifecycle.log_subprocess_dead }
        assert_includes captured.first, "subprocess died"
      end

      private

      def capture_logger(level, &block)
        captured = []
        logger = Object.new
        logger.define_singleton_method(level) { |msg| captured << msg }
        EarlScribe.stub(:logger, logger, &block)
        captured
      end

      def build_wait_thr(success:, exitstatus: 0, termsig: nil)
        wait_thr = Object.new
        status = Object.new
        status.define_singleton_method(:success?) { success }
        status.define_singleton_method(:exitstatus) { exitstatus }
        status.define_singleton_method(:termsig) { termsig }
        wait_thr.define_singleton_method(:value) { status }
        wait_thr
      end
    end
  end
end
