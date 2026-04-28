# frozen_string_literal: true

module EarlScribe
  module Cli
    # Renders rerun progress on stderr — a streaming `[####----]` bar when the
    # shim emits incremental EOU events (file-streaming mode), or a spinner
    # when it doesn't (batch mode dumps everything at end-of-pass).
    module RerunProgress
      module_function

      def paint(audio_sec, ctx)
        return unless audio_sec && ctx[:duration]&.positive? && tty?
        return if (audio_sec - ctx[:last_paint]).abs < 0.5

        ctx[:last_paint] = audio_sec
        pct = (audio_sec * 100.0 / ctx[:duration]).clamp(0.0, 100.0)
        $stderr.print(format("\r\e[K  rerun [%<bar>s] %<pct>5.1f%% (%<at>6.1f / %<dur>6.1fs)",
                             bar: bar(pct), pct: pct, at: audio_sec, dur: ctx[:duration]))
      end

      def clear
        $stderr.print("\r\e[K") if tty?
      end

      def start_spinner
        return nil unless tty?

        Thread.new do
          frames = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
          i = 0
          loop do
            $stderr.print("\r\e[K  rerun #{frames[i % frames.size]} transcribing...")
            i += 1
            sleep 0.1
          end
        end
      end

      def bar(pct, width: 30)
        filled = (width * pct / 100.0).to_i
        ("#" * filled) + ("-" * (width - filled))
      end
      private_class_method :bar

      def tty?
        $stderr.tty?
      end
      private_class_method :tty?
    end
  end
end
