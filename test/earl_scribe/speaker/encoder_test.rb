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

      private

      def mock_status(success)
        status = Minitest::Mock.new
        status.expect(:success?, success)
        status
      end
    end
  end
end
