# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Audio
    class SegmentExtractorTest < Minitest::Test
      setup do
        @tmp_dir = Dir.mktmpdir("segment_extractor_test")
      end

      teardown do
        FileUtils.rm_rf(@tmp_dir)
      end

      test "extract_wav calls ffmpeg with correct args" do
        captured_args = nil
        status = Minitest::Mock.new
        status.expect(:success?, true)

        stub = lambda do |*args|
          captured_args = args
          ["", "", status]
        end
        Open3.stub(:capture3, stub) do
          SegmentExtractor.extract_wav("/tmp/test.m4a", 1.5, 4.0, output_path: "/tmp/out.wav")
        end

        assert_includes captured_args, "ffmpeg"
        assert_includes captured_args, "-ss"
        assert_includes captured_args, "1.5"
        assert_includes captured_args, "-t"
        assert_includes captured_args, "2.5"
        assert_includes captured_args, "-ar"
        assert_includes captured_args, "16000"
        status.verify
      end

      test "extract_wav raises on ffmpeg failure" do
        status = Minitest::Mock.new
        status.expect(:success?, false)

        Open3.stub(:capture3, ["", "error msg", status]) do
          error = assert_raises(EarlScribe::Error) do
            SegmentExtractor.extract_wav("/tmp/test.m4a", 0.0, 1.0, output_path: "/tmp/out.wav")
          end
          assert_includes error.message, "ffmpeg extraction failed"
        end
        status.verify
      end

      test "extract_best_segments selects longest segments above minimum duration" do
        segments = [
          Transcription::Result.new(text: "short", start_time: 0.0, end_time: 1.0, channel: 0),
          Transcription::Result.new(text: "long one", start_time: 2.0, end_time: 5.5, channel: 0),
          Transcription::Result.new(text: "medium", start_time: 6.0, end_time: 8.5, channel: 0),
          Transcription::Result.new(text: "longest", start_time: 10.0, end_time: 16.0, channel: 0)
        ]

        status = Minitest::Mock.new
        3.times { status.expect(:success?, true) }

        Open3.stub(:capture3, ->(*_args) { ["", "", status] }) do
          results = SegmentExtractor.extract_best_segments("/tmp/test.m4a", segments, tmp_dir: @tmp_dir)
          assert_equal 3, results.size
          assert_equal "longest", results.first[:segment].text
          assert_equal "long one", results[1][:segment].text
          assert_equal "medium", results[2][:segment].text
        end
      end

      test "extract_best_segments skips segments below minimum duration" do
        segments = [
          Transcription::Result.new(text: "too short", start_time: 0.0, end_time: 1.5, channel: 0)
        ]

        results = SegmentExtractor.extract_best_segments("/tmp/test.m4a", segments, tmp_dir: @tmp_dir)
        assert_empty results
      end
    end
  end
end
