# frozen_string_literal: true

require "test_helper"
require "open3"
require "tempfile"

module EarlScribe
  module Speaker
    class EncoderTest < Minitest::Test
      # Ruby 4.0.1 can leak Minitest stubs for module singleton methods.
      # Capture the real methods at load time so tests are immune to leaks.
      REAL_ENCODE = Encoder.method(:encode)
      REAL_AVAILABLE = Encoder.method(:available?)

      test "encode returns parsed JSON embedding" do
        success = mock_status(true)
        Tempfile.create(["test", ".wav"]) do |f|
          Open3.stub(:capture3, ["[0.1, 0.2, 0.3]", "", success]) do
            result = REAL_ENCODE.call(f.path)
            assert_equal [0.1, 0.2, 0.3], result
          end
        end
      end

      test "encode raises when file not found" do
        error = assert_raises(EarlScribe::Error) { REAL_ENCODE.call("/nonexistent.wav") }
        assert_includes error.message, "Audio file not found"
      end

      test "encode raises when python helper fails" do
        failure = mock_status(false)
        Tempfile.create(["test", ".wav"]) do |f|
          Open3.stub(:capture3, ["", "ImportError: no module", failure]) do
            error = assert_raises(EarlScribe::Error) { REAL_ENCODE.call(f.path) }
            assert_includes error.message, "Speaker encoder failed"
          end
        end
      end

      test "available? returns true when resemblyzer installed" do
        success = mock_status(true)
        Open3.stub(:capture3, ["", "", success]) do
          assert REAL_AVAILABLE.call
        end
      end

      test "available? returns false when resemblyzer not installed" do
        failure = mock_status(false)
        Open3.stub(:capture3, ["", "ModuleNotFoundError", failure]) do
          assert_not REAL_AVAILABLE.call
        end
      end

      test "available? returns false when python3 not found" do
        Open3.stub(:capture3, ->(*_args) { raise Errno::ENOENT }) do
          assert_not REAL_AVAILABLE.call
        end
      end

      test "HELPER_PATH points to python script" do
        assert EarlScribe::Speaker::Encoder::HELPER_PATH.end_with?("speaker_encoder.py")
        assert File.exist?(EarlScribe::Speaker::Encoder::HELPER_PATH)
      end

      test "SERVER_PATH points to server python script" do
        assert EarlScribe::Speaker::Encoder::SERVER_PATH.end_with?("speaker_encoder_server.py")
        assert File.exist?(EarlScribe::Speaker::Encoder::SERVER_PATH)
      end

      private

      def mock_status(success)
        status = Minitest::Mock.new
        status.expect(:success?, success)
        status
      end
    end

    class PersistentProcessTest < Minitest::Test
      test "encode returns embedding from server response" do
        stdin, stdout, process = build_mock_process
        stdout.string = "{\"status\": \"ready\"}\n{\"id\": \"abc\", \"embedding\": [0.1, 0.2, 0.3]}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder::PersistentProcess.new
          result = pp.encode("/tmp/test.wav")
          assert_equal [0.1, 0.2, 0.3], result
          pp.shutdown
        end
      end

      test "encode raises on error response" do
        stdin, stdout, process = build_mock_process
        stdout.string = "{\"status\": \"ready\"}\n{\"id\": \"abc\", \"error\": \"file not found\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder::PersistentProcess.new
          error = assert_raises(EarlScribe::Error) { pp.encode("/tmp/test.wav") }
          assert_includes error.message, "file not found"
          pp.shutdown
        end
      end

      test "encode raises when process dies" do
        stdin, stdout, process = build_mock_process(alive: false)
        stdout.string = "{\"status\": \"ready\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder::PersistentProcess.new
          process.define_singleton_method(:alive?) { false }
          error = assert_raises(EarlScribe::Error) { pp.encode("/tmp/test.wav") }
          assert_includes error.message, "not running"
          pp.shutdown
        end
      end

      test "shutdown sends shutdown command" do
        stdin, stdout, process = build_mock_process
        stdout.string = "{\"status\": \"ready\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder::PersistentProcess.new
          pp.shutdown
          assert_includes stdin.string, "shutdown"
        end
      end

      test "encode raises when process returns nil response" do
        stdin, stdout, process = build_mock_process
        stdout.string = "{\"status\": \"ready\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder::PersistentProcess.new
          error = assert_raises(EarlScribe::Error) { pp.encode("/tmp/test.wav") }
          assert_includes error.message, "process died"
          pp.shutdown
        end
      end

      test "raises when server fails to start" do
        stdin, stdout, process = build_mock_process
        stdout.string = "{\"error\": \"import failed\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          error = assert_raises(EarlScribe::Error) { Encoder::PersistentProcess.new }
          assert_includes error.message, "failed to start"
        end
      end

      test "raises when server returns nil on startup" do
        stdin, stdout, process = build_mock_process
        stdout.string = ""
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          error = assert_raises(EarlScribe::Error) { Encoder::PersistentProcess.new }
          assert_includes error.message, "failed to start"
        end
      end

      test "shutdown is safe when process already dead" do
        stdin, stdout, process = build_mock_process(alive: false)
        stdout.string = "{\"status\": \"ready\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder::PersistentProcess.new
          process.define_singleton_method(:alive?) { false }
          pp.shutdown # should not raise
        end
      end

      test "alive? returns false when wait_thread is nil" do
        stdin, stdout, process = build_mock_process
        stdout.string = "{\"status\": \"ready\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder::PersistentProcess.new
          pp.instance_variable_set(:@wait_thread, nil)
          assert_not pp.alive?
          pp.shutdown
        end
      end

      test "close_io handles nil IO objects" do
        stdin, stdout, process = build_mock_process(alive: false)
        stdout.string = "{\"status\": \"ready\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder::PersistentProcess.new
          # Simulate already-closed state
          pp.instance_variable_set(:@stdin, nil)
          pp.instance_variable_set(:@stdout, nil)
          pp.instance_variable_set(:@stderr, nil)
          pp.instance_variable_set(:@wait_thread, nil)
          pp.shutdown # should not raise
        end
      end

      test "start_server returns PersistentProcess instance" do
        stdin, stdout, process = build_mock_process
        stdout.string = "{\"status\": \"ready\"}\n"
        stdout.rewind

        Open3.stub(:popen3, [stdin, stdout, StringIO.new, process]) do
          pp = Encoder.start_server
          assert_instance_of Encoder::PersistentProcess, pp
          pp.shutdown
        end
      end

      private

      def build_mock_process(alive: true)
        stdin = StringIO.new
        stdin.define_singleton_method(:flush) { nil }
        stdout = StringIO.new
        process = Object.new
        process.define_singleton_method(:alive?) { alive }
        process.define_singleton_method(:value) { nil }
        [stdin, stdout, process]
      end
    end
  end
end
