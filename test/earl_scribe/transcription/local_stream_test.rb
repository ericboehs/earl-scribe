# frozen_string_literal: true

require "test_helper"
require "stringio"

module EarlScribe
  module Transcription
    class LocalStreamTest < Minitest::Test
      test "rejects multi-channel input" do
        assert_raises(ArgumentError) do
          LocalStream.new(channels: 2)
        end
      end

      test "build_command picks s16_48k_mono at 48k" do
        client = LocalStream.new(asr_bin: "/tmp/asr", chunk_ms: 320)
        cmd = client.build_command
        assert_equal "/tmp/asr", cmd.first
        assert_includes cmd, "--stdin"
        assert_includes cmd, "--stdin-format"
        assert_includes cmd, "s16_48k_mono"
        assert_includes cmd, "--chunk-ms"
        assert_includes cmd, "320"
      end

      test "build_command picks f32_16k_mono at 16k" do
        client = LocalStream.new(asr_bin: "/tmp/asr", sample_rate: 16_000)
        assert_equal "f32_16k_mono", client.stdin_format
      end

      test "send_audio writes to subprocess stdin" do
        client = LocalStream.new(asr_bin: "/tmp/asr")
        stdin = StringIO.new
        stdin.binmode
        client.instance_variable_set(:@stdin, stdin)

        client.send_audio("\x01\x02\x03")
        assert_equal "\x01\x02\x03", stdin.string
      end

      test "send_audio swallows EPIPE when subprocess died" do
        client = LocalStream.new(asr_bin: "/tmp/asr")
        broken = Object.new
        broken.define_singleton_method(:write) { |_| raise Errno::EPIPE }
        client.instance_variable_set(:@stdin, broken)

        assert_nothing_raised { client.send_audio("data") }
      end

      test "connect spawns subprocess and pipes events to callback" do
        eou_line = "{\"type\":\"eou\",\"text\":\"hello\",\"audio_sec\":1.2}\n"
        stdout = StringIO.new(eou_line)
        stdout.binmode
        stderr = StringIO.new
        stderr.binmode
        stdin = StringIO.new
        stdin.binmode
        wait_thr = Object.new
        wait_thr.define_singleton_method(:value) { nil }

        captured_cmd = nil
        Open3.stub(:popen3, lambda { |*cmd|
          captured_cmd = cmd
          [stdin, stdout, stderr, wait_thr]
        }) do
          received = []
          client = LocalStream.new(asr_bin: "/tmp/asr")
          client.connect(->(result) { received << result })
          client.close

          assert_equal "/tmp/asr", captured_cmd.first
          assert_equal 1, received.size
          assert_equal "hello", received.first[:transcript]
        end
      end

      test "close is idempotent and clears handles" do
        client = LocalStream.new(asr_bin: "/tmp/asr")
        client.close
        assert_nil client.instance_variable_get(:@stdin)
      end

      test "connect raises a friendly error when the binary is missing" do
        Open3.stub(:popen3, ->(*_) { raise Errno::ENOENT }) do
          client = LocalStream.new(asr_bin: "/no/such/asr")
          error = assert_raises(EarlScribe::Error) { client.connect(->(_) {}) }
          assert_includes error.message, "/no/such/asr"
          assert_includes error.message, "bin/build-asr"
        end
      end

      test "send_audio with nil stdin no-ops" do
        client = LocalStream.new(asr_bin: "/tmp/asr")
        assert_nothing_raised { client.send_audio("data") }
      end

      test "dispatches error events to logger" do
        line = "{\"type\":\"error\",\"message\":\"boom\"}\n"
        run_with_stdout(line) do |received, log_calls|
          assert_empty received
          assert_includes log_calls[:error].first, "boom"
        end
      end

      test "dispatches malformed events to logger at error severity" do
        line = "{this is not json}\n"
        run_with_stdout(line) do |received, log_calls|
          assert_empty received
          assert(log_calls[:error].any? { |m| m.include?("not json") })
        end
      end

      test "skips eou event with empty text" do
        line = "{\"type\":\"eou\",\"text\":\"\",\"audio_sec\":1.0}\n"
        run_with_stdout(line) do |received, _log_calls|
          assert_empty received
        end
      end

      test "partial events are silently ignored" do
        line = "{\"type\":\"partial\",\"text\":\"hi\"}\n"
        assert_nothing_raised { run_with_stdout(line) }
      end

      test "ignores unknown event types without raising" do
        line = "{\"type\":\"unknown_thing\"}\n"
        run_with_stdout(line) do |received, log_calls|
          assert_empty received
          assert_empty log_calls[:warn]
          assert_empty log_calls[:error]
        end
      end

      test "send_audio logs once when subprocess dies and stays silent after" do
        log_calls = capture_logger do |logger|
          client = LocalStream.new(asr_bin: "/tmp/asr")
          broken = Object.new
          broken.define_singleton_method(:write) { |_| raise Errno::EPIPE }
          client.instance_variable_set(:@stdin, broken)
          EarlScribe.stub(:logger, logger) do
            3.times { client.send_audio("data") }
          end
        end
        died = log_calls[:error].select { |m| m.include?("subprocess died") }
        assert_equal 1, died.size, "expected exactly one death notification"
      end

      test "error events flag subprocess as dead so subsequent send_audio is silent" do
        line = "{\"type\":\"error\",\"message\":\"boom\"}\n"
        run_with_stdout(line) do |_received, log_calls|
          assert(log_calls[:error].any? { |m| m.include?("boom") })
        end
      end

      test "close logs warning when subprocess exits with non-zero status" do
        bad_status = Object.new
        bad_status.define_singleton_method(:success?) { false }
        bad_status.define_singleton_method(:exitstatus) { 2 }
        bad_status.define_singleton_method(:termsig) { nil }
        log_calls = capture_logger do |logger|
          client = LocalStream.new(asr_bin: "/tmp/asr")
          client.instance_variable_set(:@wait_thr, fake_wait_thr(bad_status))
          EarlScribe.stub(:logger, logger) { client.close }
        end
        assert(log_calls[:error].any? { |m| m.include?("exited 2") })
      end

      test "close logs signal when subprocess killed by signal" do
        sig_status = Object.new
        sig_status.define_singleton_method(:success?) { false }
        sig_status.define_singleton_method(:exitstatus) { nil }
        sig_status.define_singleton_method(:termsig) { 9 }
        log_calls = capture_logger do |logger|
          client = LocalStream.new(asr_bin: "/tmp/asr")
          client.instance_variable_set(:@wait_thr, fake_wait_thr(sig_status))
          EarlScribe.stub(:logger, logger) { client.close }
        end
        assert(log_calls[:error].any? { |m| m.include?("signal 9") })
      end

      test "close warns when reader thread does not exit within timeout" do
        slow_reader = Thread.new { sleep 60 }
        log_calls = capture_logger do |logger|
          client = LocalStream.new(asr_bin: "/tmp/asr")
          client.instance_variable_set(:@reader, slow_reader)
          stub_const(LocalStream, :CLOSE_READER_TIMEOUT, 0.05) do
            EarlScribe.stub(:logger, logger) { client.close }
          end
        end
        slow_reader.kill
        assert(log_calls[:warn].any? { |m| m.include?("did not exit") })
      end

      test "connect raises a friendly error when binary is not executable" do
        Open3.stub(:popen3, ->(*_) { raise Errno::EACCES }) do
          client = LocalStream.new(asr_bin: "/tmp/asr")
          error = assert_raises(EarlScribe::Error) { client.connect(->(_) {}) }
          assert_match(/not executable/, error.message)
        end
      end

      test "connect raises a friendly error when binary is wrong arch" do
        Open3.stub(:popen3, ->(*_) { raise Errno::ENOEXEC }) do
          client = LocalStream.new(asr_bin: "/tmp/asr")
          error = assert_raises(EarlScribe::Error) { client.connect(->(_) {}) }
          assert_match(/wrong architecture/, error.message)
        end
      end

      test "reader thread crash logs at error and notifies subprocess dead" do
        line = "{\"type\":\"eou\",\"text\":\"x\",\"audio_sec\":1}\n"
        log_calls = capture_logger do |logger|
          stdout = StringIO.new(line)
          stdout.binmode
          stderr = StringIO.new
          stderr.binmode
          stdin = StringIO.new
          stdin.binmode
          Open3.stub(:popen3, ->(*_) { [stdin, stdout, stderr, fake_wait_thr] }) do
            EarlScribe.stub(:logger, logger) do
              client = LocalStream.new(asr_bin: "/tmp/asr")
              client.connect(->(_) { raise "callback exploded" })
              client.close
            end
          end
        end
        assert(log_calls[:error].any? { |m| m.include?("reader thread crashed") })
      end

      test "drain_stderr forwards stderr lines to logger" do
        log_calls = capture_logger do |logger|
          stdout = StringIO.new("")
          stdout.binmode
          stderr = StringIO.new("loading model\n")
          stderr.binmode
          stdin = StringIO.new
          stdin.binmode
          Open3.stub(:popen3, ->(*_) { [stdin, stdout, stderr, fake_wait_thr] }) do
            EarlScribe.stub(:logger, logger) do
              client = LocalStream.new(asr_bin: "/tmp/asr")
              client.connect(->(_) {})
              client.close
            end
          end
        end
        assert(log_calls[:warn].any? { |m| m.include?("loading model") })
      end

      private

      def fake_wait_thr(status = nil)
        wt = Object.new
        wt.define_singleton_method(:value) { status }
        wt
      end

      def capture_logger
        calls = { error: [], warn: [] }
        logger = Logger.new(StringIO.new)
        logger.define_singleton_method(:error) { |m| calls[:error] << m }
        logger.define_singleton_method(:warn) { |m| calls[:warn] << m }
        yield logger
        calls
      end

      def stub_const(mod, name, value)
        original = mod.const_get(name)
        mod.send(:remove_const, name)
        mod.const_set(name, value)
        yield
      ensure
        mod.send(:remove_const, name)
        mod.const_set(name, original)
      end

      def run_with_stdout(line)
        stdout = StringIO.new(line)
        stdout.binmode
        stderr = StringIO.new
        stderr.binmode
        stdin = StringIO.new
        stdin.binmode
        wait_thr = Object.new
        wait_thr.define_singleton_method(:value) { nil }

        log_calls = { error: [], warn: [] }
        logger = Logger.new(StringIO.new)
        logger.define_singleton_method(:error) { |msg| log_calls[:error] << msg }
        logger.define_singleton_method(:warn) { |msg| log_calls[:warn] << msg }

        Open3.stub(:popen3, ->(*_) { [stdin, stdout, stderr, wait_thr] }) do
          EarlScribe.stub(:logger, logger) do
            received = []
            client = LocalStream.new(asr_bin: "/tmp/asr")
            client.connect(->(r) { received << r })
            client.close
            yield received, log_calls if block_given?
          end
        end
      end
    end
  end
end
