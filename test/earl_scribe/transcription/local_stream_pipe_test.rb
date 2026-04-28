# frozen_string_literal: true

require "stringio"
require "test_helper"

module EarlScribe
  module Transcription
    class LocalStreamPipeTest < Minitest::Test
      def test_sox_command_resamples_s16_48k_to_f32_16k
        cmd = LocalStreamPipe.sox_command
        assert_equal "sox", cmd.first
        assert_includes cmd, "48000"
        assert_includes cmd, "16000"
        assert_includes cmd, "signed-integer"
        assert_includes cmd, "floating-point"
        assert_includes cmd, "32" # bit depth for output
      end

      def test_close_is_noop_for_nil_pipe
        target = StringIO.new
        assert_nil LocalStreamPipe.close(nil, target)
      end

      def test_copy_stream_swallows_epipe
        source = Object.new
        source.define_singleton_method(:gets) { nil }
        target = Object.new
        IO.stub(:copy_stream, ->(_s, _t) { raise Errno::EPIPE }) do
          assert_nil LocalStreamPipe.copy_stream(source, target)
        end
      end

      def test_copy_stream_swallows_io_error
        IO.stub(:copy_stream, ->(_s, _t) { raise IOError }) do
          assert_nil LocalStreamPipe.copy_stream(:src, :tgt)
        end
      end

      def test_close_orchestrates_pipe_shutdown
        pipe = build_fake_pipe(stdin_closed: false)
        target = StringIO.new
        LocalStreamPipe.close(pipe, target)
        assert pipe.stdin.closed?
        assert_predicate target, :closed?
      end

      def test_close_skips_closed_target
        pipe = build_fake_pipe(stdin_closed: false)
        target = StringIO.new
        target.close
        # Should not raise
        LocalStreamPipe.close(pipe, target)
        assert pipe.stdin.closed?
      end

      private

      def build_fake_pipe(stdin_closed:)
        stdin = StringIO.new
        stdin.close if stdin_closed
        wait_thr = Object.new
        wait_thr.define_singleton_method(:value) { Object.new }
        pump = Thread.new { :ok }
        stderr = Thread.new { :ok }
        LocalStreamPipe::Pipe.new(stdin: stdin, wait_thr: wait_thr,
                                  pump_thread: pump, stderr_thread: stderr)
      end
    end
  end
end
