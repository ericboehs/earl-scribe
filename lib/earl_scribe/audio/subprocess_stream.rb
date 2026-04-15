# frozen_string_literal: true

module EarlScribe
  module Audio
    # Wraps an audio-producing subprocess (audiotee, sox, etc.) with background
    # stderr drainage so capture failures surface with useful diagnostics
    # instead of silently producing zero audio.
    class SubprocessStream
      attr_reader :io, :name, :stderr_buffer

      def self.spawn(cmd)
        err_r, err_w = IO.pipe
        begin
          # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
          io = IO.popen(cmd, "rb", err: err_w)
        rescue Errno::ENOENT => error
          err_r.close
          err_w.close
          raise EarlScribe::Error, "#{cmd.first} not found on PATH. (#{error.message})"
        end
        err_w.close
        new(io, err_r, cmd.first)
      end

      def initialize(io, err_r, name)
        @io = io
        @name = name
        @stderr_buffer = +""
        @stderr_thread = Thread.new { drain(err_r) }
      end

      def read(bytes)
        @io&.read(bytes)
      end

      def stop
        return unless @io

        Process.kill("TERM", @io.pid)
        @io.close
      rescue Errno::ESRCH, Errno::EPERM, IOError
        nil
      ensure
        @io = nil
        @stderr_thread&.join(2)
      end

      def stderr_tail(lines: 10)
        @stderr_buffer.split("\n").last(lines).join("\n").strip
      end

      private

      def drain(err_r)
        while (chunk = err_r.read(4096))
          @stderr_buffer << chunk
        end
      rescue IOError
        nil
      ensure
        close_quietly(err_r)
      end

      def close_quietly(io)
        io.close
      rescue IOError
        nil
      end
    end
  end
end
