# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Audio
    class SubprocessStreamTest < Minitest::Test
      test "spawn raises EarlScribe::Error when binary missing" do
        IO.stub(:popen, ->(*_args, **_opts) { raise Errno::ENOENT, "no such file" }) do
          error = assert_raises(EarlScribe::Error) do
            EarlScribe::Audio::SubprocessStream.spawn(["nonexistent-bin"])
          end
          assert_includes error.message, "nonexistent-bin"
          assert_includes error.message, "not found"
        end
      end

      test "read proxies to wrapped IO" do
        io = StringIO.new("hello")
        io.define_singleton_method(:pid) { 99_999 }
        stream = build_stream(io)

        assert_equal "hello", stream.read(5)
      end

      test "stderr_tail returns last N lines from buffer" do
        io = StringIO.new("")
        io.define_singleton_method(:pid) { 99_999 }
        stream = build_stream(io)
        buffer = stream.instance_variable_get(:@stderr_buffer)
        15.times { |i| buffer << "line#{i}\n" }

        tail = stream.stderr_tail(lines: 3)
        assert_includes tail, "line12"
        assert_includes tail, "line14"
        assert_not_includes tail, "line10"
      end

      test "stderr drainer accumulates subprocess stderr into buffer" do
        io = StringIO.new("")
        io.define_singleton_method(:pid) { 99_999 }
        err_r, err_w = IO.pipe
        stream = EarlScribe::Audio::SubprocessStream.new(io, err_r, "test")
        err_w.write("oh no\nbroken pipe\n")
        err_w.close
        Thread.pass
        sleep 0.05 # let drainer thread consume

        assert_includes stream.stderr_buffer, "broken pipe"
      end

      test "stop kills subprocess and rescues ESRCH/EPERM/IOError" do
        io = Object.new
        io.define_singleton_method(:pid) { 99_999 }
        io.define_singleton_method(:close) { nil }
        stream = build_stream(io)

        Process.stub(:kill, ->(*_args) { raise Errno::ESRCH }) do
          assert_nothing_raised { stream.stop }
        end
      end

      test "stop is a no-op after first call" do
        io = StringIO.new("")
        io.define_singleton_method(:pid) { 99_999 }
        stream = build_stream(io)

        Process.stub(:kill, ->(*_args) {}) do
          stream.stop
          assert_nothing_raised { stream.stop }
        end
      end

      test "read returns nil after stop" do
        io = StringIO.new("data")
        io.define_singleton_method(:pid) { 99_999 }
        stream = build_stream(io)

        Process.stub(:kill, ->(*_args) {}) do
          stream.stop
        end

        assert_nil stream.read(4)
      end

      private

      def build_stream(io)
        err_r, err_w = IO.pipe
        err_w.close
        EarlScribe::Audio::SubprocessStream.new(io, err_r, "test")
      end
    end
  end
end
