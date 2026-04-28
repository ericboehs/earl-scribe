# frozen_string_literal: true

require "open3"

module EarlScribe
  module Transcription
    # Optional sox-based format converter that sits between Ruby's audio
    # capture (raw S16LE 48k mono) and a downstream subprocess that needs a
    # different format. Used by LocalStream when the engine wants Float32 16k
    # mono (WhisperKit) but capture is delivering 48k S16LE. Owns its own
    # sox subprocess + stdout-pump thread.
    module LocalStreamPipe
      module_function

      Pipe = Struct.new(:stdin, :wait_thr, :pump_thread, :stderr_thread, keyword_init: true)

      def open(target_stdin)
        cmd = sox_command
        sox_stdin, sox_stdout, sox_stderr, wait_thr = Open3.popen3(*cmd)
        [sox_stdin, sox_stdout, sox_stderr].each(&:binmode)
        pump = Thread.new { copy_stream(sox_stdout, target_stdin) }
        drain = Thread.new { sox_stderr.read }
        Pipe.new(stdin: sox_stdin, wait_thr: wait_thr, pump_thread: pump, stderr_thread: drain)
      end

      def close(pipe, target_stdin)
        return unless pipe

        pipe.stdin.close
        pipe.pump_thread.join(5)
        target_stdin.close unless target_stdin.closed?
        pipe.stderr_thread.join(1)
        pipe.wait_thr.value
      end

      def sox_command
        ["sox",
         "-t", "raw", "-e", "signed-integer", "-b", "16",
         "-r", "48000", "-c", "1", "-",
         "-t", "raw", "-e", "floating-point", "-b", "32",
         "-r", "16000", "-c", "1", "-"]
      end

      def copy_stream(source, target)
        IO.copy_stream(source, target)
      rescue Errno::EPIPE, IOError
        nil
      end
    end
  end
end
