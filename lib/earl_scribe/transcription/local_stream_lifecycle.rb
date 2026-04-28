# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Subprocess lifecycle helpers for LocalStream — signal forwarding,
    # exit-status logging, and the reader-hang warning. Lifted out to keep
    # LocalStream under the lint length budget.
    module LocalStreamLifecycle
      module_function

      SPAWN_ERROR_REASONS = { Errno::ENOENT => "not found", Errno::EACCES => "is not executable",
                              Errno::ENOEXEC => "is the wrong architecture" }.freeze

      def spawn_error_reason(error)
        SPAWN_ERROR_REASONS.fetch(error.class, "could not be spawned")
      end

      def signal_subprocess(wait_thr, sig)
        pid = wait_thr&.pid
        Process.kill(sig, pid) if pid
      rescue Errno::ESRCH, Errno::EINVAL
        nil
      end

      def warn_if_reader_hung(hung, timeout_sec)
        return unless hung

        EarlScribe.logger.warn("earl-scribe-asr reader did not exit within #{timeout_sec}s")
      end

      def check_exit_status(wait_thr)
        status = wait_thr&.value
        return unless status && !status.success?

        EarlScribe.logger.error(
          "earl-scribe-asr exited #{status.exitstatus || "via signal #{status.termsig}"}"
        )
      end

      def log_subprocess_dead
        EarlScribe.logger.error("earl-scribe-asr subprocess died; dropping subsequent audio")
      end
    end
  end
end
