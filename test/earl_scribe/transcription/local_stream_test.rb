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
        assert_includes client.build_command, "f32_16k_mono"
      end

      test "build_command appends --no-diarize when diarize is false" do
        client = LocalStream.new(asr_bin: "/tmp/asr", diar: { enabled: false })
        assert_includes client.build_command, "--no-diarize"
      end

      test "build_command omits diarization flags by default" do
        client = LocalStream.new(asr_bin: "/tmp/asr")
        cmd = client.build_command
        assert_not_includes cmd, "--no-diarize"
        assert_not_includes cmd, "--diar-debug"
      end

      test "build_command appends --diar-debug when diar[:debug] is true" do
        client = LocalStream.new(asr_bin: "/tmp/asr", diar: { debug: true })
        assert_includes client.build_command, "--diar-debug"
      end

      test "build_command passes --diar-variant when diar[:variant] is set" do
        client = LocalStream.new(asr_bin: "/tmp/asr", diar: { variant: "fastV2" })
        cmd = client.build_command
        assert_includes cmd, "--diar-variant"
        assert_includes cmd, "fastV2"
      end

      test "build_command swaps stdin for --capture in native mode" do
        client = LocalStream.new(asr_bin: "/tmp/asr", native: { mic: true })
        cmd = client.build_command
        assert_includes cmd, "--capture"
        assert_not_includes cmd, "--stdin"
        assert_not_includes cmd, "--stdin-format"
      end

      test "build_command appends --no-mic in native mode without mic" do
        client = LocalStream.new(asr_bin: "/tmp/asr", native: { mic: false })
        assert_includes client.build_command, "--no-mic"
      end

      test "build_command omits --no-mic when native mic is on" do
        client = LocalStream.new(asr_bin: "/tmp/asr", native: { mic: true })
        assert_not_includes client.build_command, "--no-mic"
      end

      test "build_command appends --capture-wav when wav_path is set" do
        client = LocalStream.new(asr_bin: "/tmp/asr", native: { mic: true, wav_path: "/tmp/x.wav" })
        cmd = client.build_command
        assert_includes cmd, "--capture-wav"
        assert_includes cmd, "/tmp/x.wav"
      end

      test "native? reports the native flag" do
        assert LocalStream.new(asr_bin: "/tmp/asr", native: { mic: true }).native?
        assert_not LocalStream.new(asr_bin: "/tmp/asr").native?
      end

      test "build_command in whisperkit engine uses --model-path with no chunk-ms or diar flags" do
        Config.stub(:whisperkit_model, "/m") do
          client = LocalStream.new(asr_bin: "/tmp/wk", engine: :whisperkit)
          assert_equal ["/tmp/wk", "--model-path", "/m"], client.build_command
        end
      end

      test "whisperkit engine raises when model is missing" do
        Config.stub(:whisperkit_model, nil) do
          client = LocalStream.new(asr_bin: "/tmp/wk", engine: :whisperkit)
          assert_raises(EarlScribe::Error) { client.build_command }
        end
      end

      test "whisperkit engine resolves binary from Config.whisperkit_bin" do
        Config.stub(:whisperkit_bin, "/tmp/wkbin") do
          Config.stub(:whisperkit_model, "/m") do
            client = LocalStream.new(engine: :whisperkit)
            assert_equal "/tmp/wkbin", client.build_command.first
          end
        end
      end

      test "wait_until_done is no-op when no subprocess started" do
        client = LocalStream.new(asr_bin: "/tmp/asr")
        client.wait_until_done # should not raise
      end

      test "send_audio is no-op when stdin nil" do
        client = LocalStream.new(asr_bin: "/tmp/asr")
        client.send_audio("data") # should not raise
      end

      test "close is no-op before connect" do
        client = LocalStream.new(asr_bin: "/tmp/asr")
        client.close # should not raise
      end

      test "channels accessor returns 1" do
        assert_equal 1, LocalStream.new(asr_bin: "/tmp/asr").channels
      end

      test "native? true when native opts set" do
        assert LocalStream.new(asr_bin: "/tmp/asr", native: { mic: true }).native?
      end

      test "wait_until_done joins the wait thread" do
        client = LocalStream.new(asr_bin: "/tmp/asr", native: { mic: true })
        joined = false
        wait_thr = Object.new
        wait_thr.define_singleton_method(:join) { joined = true }
        wait_thr.define_singleton_method(:pid) { 12_345 }
        client.instance_variable_set(:@wait_thr, wait_thr)
        client.wait_until_done
        assert joined
      end

      test "wait_until_done forwards Interrupt to subprocess and re-raises" do
        client = LocalStream.new(asr_bin: "/tmp/asr", native: { mic: true })
        signaled = nil
        join_count = 0
        wait_thr = Object.new
        wait_thr.define_singleton_method(:join) do
          join_count += 1
          raise Interrupt if join_count == 1
        end
        wait_thr.define_singleton_method(:pid) { 12_345 }
        client.instance_variable_set(:@wait_thr, wait_thr)

        Process.stub(:kill, ->(sig, _pid) { signaled = sig }) do
          assert_raises(Interrupt) { client.wait_until_done }
        end
        assert_equal :INT, signaled
        assert_equal 2, join_count
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
