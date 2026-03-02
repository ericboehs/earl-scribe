# frozen_string_literal: true

require "test_helper"
require "open3"

module EarlScribe
  module Speaker
    class EncoderTest < Minitest::Test
      test "encode returns parsed JSON embedding" do
        success = mock_status(true)
        File.stub(:exist?, true) do
          Open3.stub(:capture3, ["[0.1, 0.2, 0.3]", "", success]) do
            result = EarlScribe::Speaker::Encoder.encode("/tmp/test.wav")
            assert_equal [0.1, 0.2, 0.3], result
          end
        end
      end

      test "encode raises when file not found" do
        error = assert_raises(EarlScribe::Error) { EarlScribe::Speaker::Encoder.encode("/nonexistent.wav") }
        assert_includes error.message, "Audio file not found"
      end

      test "encode raises when python helper fails" do
        failure = mock_status(false)
        File.stub(:exist?, true) do
          Open3.stub(:capture3, ["", "ImportError: no module", failure]) do
            error = assert_raises(EarlScribe::Error) { EarlScribe::Speaker::Encoder.encode("/tmp/test.wav") }
            assert_includes error.message, "Speaker encoder failed"
          end
        end
      end

      test "available? returns true when resemblyzer installed" do
        success = mock_status(true)
        Open3.stub(:capture3, ["", "", success]) do
          assert EarlScribe::Speaker::Encoder.available?
        end
      end

      test "available? returns false when resemblyzer not installed" do
        failure = mock_status(false)
        Open3.stub(:capture3, ["", "ModuleNotFoundError", failure]) do
          assert_not EarlScribe::Speaker::Encoder.available?
        end
      end

      test "available? returns false when python3 not found" do
        Open3.stub(:capture3, ->(*_args) { raise Errno::ENOENT }) do
          assert_not EarlScribe::Speaker::Encoder.available?
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
