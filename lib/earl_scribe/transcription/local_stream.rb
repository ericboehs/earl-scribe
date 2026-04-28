# frozen_string_literal: true

require "open3"

require_relative "local_stream_command"
require_relative "local_stream_lifecycle"
require_relative "local_stream_pipe"
require_relative "local_stream_reader"

module EarlScribe
  module Transcription
    # Drives a local ASR shim subprocess (FluidAudio Parakeet or WhisperKit)
    # for streaming transcription. Owns subprocess lifecycle, audio piping,
    # and clean teardown; delegates JSONL event reading to LocalStreamReader.
    class LocalStream
      attr_reader :channels, :sample_rate

      CLOSE_READER_TIMEOUT = 30
      CLOSE_STDERR_TIMEOUT = 2

      def initialize(channels: 1, sample_rate: 48_000, engine: :fluidaudio, **opts)
        raise ArgumentError, "LocalStream requires mono (channels: 1)" unless channels == 1

        @channels = channels
        @sample_rate = sample_rate
        @engine = engine
        configure(opts)
        reset_handles
      end

      def configure(opts)
        @asr_bin = opts[:asr_bin] || (whisperkit? ? Config.whisperkit_bin : Config.asr_bin)
        @chunk_ms = opts[:chunk_ms] || Config.asr_chunk_ms
        @diar = opts[:diar] || {}
        @native = opts[:native] && native_opts(opts[:native])
        @parser = LocalStreamEventParser.new
        @subprocess_dead = false
      end

      def native_opts(native)
        { mic: native[:mic] != false, wav_path: native[:wav_path] }
      end

      def whisperkit?
        @engine == :whisperkit
      end

      def native?
        !@native.nil?
      end

      # Block until the subprocess exits or the calling thread is interrupted.
      def wait_until_done
        @wait_thr&.join
      rescue Interrupt
        LocalStreamLifecycle.signal_subprocess(@wait_thr, :INT)
        @wait_thr&.join
        raise
      end

      def connect(callback)
        spawn_shim
        wrap_stdin
        start_reader_threads(callback)
      rescue Errno::ENOENT, Errno::EACCES, Errno::ENOEXEC => error
        reason = LocalStreamLifecycle.spawn_error_reason(error)
        raise Error, "earl-scribe-asr binary at #{@asr_bin.inspect} #{reason}. " \
                     "Rebuild via `bin/build-asr` and set EARL_SCRIBE_ASR_BIN."
      end

      def send_audio(data)
        @stdin&.write(data)
      rescue Errno::EPIPE, IOError
        notify_subprocess_dead
      end

      def close
        close_input
        hung = @reader && !@reader.join(CLOSE_READER_TIMEOUT)
        LocalStreamLifecycle.warn_if_reader_hung(hung, CLOSE_READER_TIMEOUT)
        @stderr_drain&.join(CLOSE_STDERR_TIMEOUT)
        @stdout&.close
        @stderr&.close
        LocalStreamLifecycle.check_exit_status(@wait_thr)
      ensure
        reset_handles
      end

      def build_command
        LocalStreamCommand.build(asr_bin: @asr_bin, chunk_ms: @chunk_ms, diar: @diar,
                                 native: @native, sample_rate: sample_rate, engine: @engine)
      end

      private

      def spawn_shim
        @shim_stdin, @stdout, @stderr, @wait_thr = Open3.popen3(*build_command)
        [@shim_stdin, @stdout, @stderr].each(&:binmode)
      end

      def wrap_stdin
        @stdin = if wrap_with_resample?
                   @sox = LocalStreamPipe.open(@shim_stdin)
                   @sox.stdin
                 else
                   @shim_stdin
                 end
      end

      def start_reader_threads(callback)
        reader = LocalStreamReader.new(stdout: @stdout, stderr: @stderr, parser: @parser,
                                       callback: callback,
                                       on_subprocess_dead: -> { notify_subprocess_dead })
        @reader = Thread.new { reader.read_loop }
        @stderr_drain = Thread.new { reader.drain_stderr }
      end

      def wrap_with_resample?
        whisperkit? && sample_rate != 16_000
      end

      def close_input
        @sox ? LocalStreamPipe.close(@sox, @shim_stdin) : @stdin&.close
      end

      def notify_subprocess_dead
        return if @subprocess_dead

        @subprocess_dead = true
        LocalStreamLifecycle.log_subprocess_dead
      end

      def reset_handles
        @stdin = @stdout = @stderr = @wait_thr = @reader = @stderr_drain = nil
        @shim_stdin = @sox = nil
      end
    end
  end
end
