# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

module EarlScribe
  module Transcription
    class JsonlWriterTest < Minitest::Test
      setup do
        @tmp_dir = Dir.mktmpdir("jsonl_writer_test")
        @path = File.join(@tmp_dir, "test.jsonl")
      end

      teardown do
        FileUtils.rm_rf(@tmp_dir)
      end

      test "write_metadata writes JSON line with type metadata" do
        writer = JsonlWriter.new(@path)
        writer.write_metadata(recorded_at: "2026-03-03T13:00:00-06:00", meeting_title: "Standup")
        writer.close

        lines = File.readlines(@path)
        assert_equal 1, lines.size
        data = JSON.parse(lines.first)
        assert_equal "metadata", data["type"]
        assert_equal "Standup", data["meeting_title"]
        assert_equal "2026-03-03T13:00:00-06:00", data["recorded_at"]
      end

      test "write_segment writes result as JSON line" do
        writer = JsonlWriter.new(@path)
        result = Result.new(speaker: "Alice", text: "Hello", start_time: 1.0, end_time: 2.5, channel: 0)
        writer.write_segment(result)
        writer.close

        lines = File.readlines(@path)
        assert_equal 1, lines.size
        data = JSON.parse(lines.first)
        assert_equal "Alice", data["speaker"]
        assert_equal "Hello", data["text"]
        assert_in_delta 1.0, data["start_time"]
        assert_in_delta 2.5, data["end_time"]
        assert_equal 0, data["channel"]
      end

      test "write_segment appends multiple lines" do
        writer = JsonlWriter.new(@path)
        writer.write_segment(Result.new(speaker: "A", text: "one", start_time: 0.0, end_time: 1.0))
        writer.write_segment(Result.new(speaker: "B", text: "two", start_time: 1.0, end_time: 2.0))
        writer.close

        lines = File.readlines(@path)
        assert_equal 2, lines.size
      end

      test "write_segment does nothing after close" do
        writer = JsonlWriter.new(@path)
        writer.write_segment(Result.new(speaker: "A", text: "before", start_time: 0.0, end_time: 1.0))
        writer.close
        writer.write_segment(Result.new(speaker: "B", text: "after", start_time: 1.0, end_time: 2.0))

        lines = File.readlines(@path)
        assert_equal 1, lines.size
      end

      test "creates parent directories" do
        path = File.join(@tmp_dir, "nested", "dir", "test.jsonl")
        writer = JsonlWriter.new(path)
        writer.write_metadata(recorded_at: "now")
        writer.close

        assert File.exist?(path)
      end

      test "handles write errors gracefully" do
        writer = JsonlWriter.new(@path)
        writer.write_metadata(recorded_at: "now")

        FileUtils.rm_rf(@tmp_dir)
        FileUtils.mkdir_p(@tmp_dir)
        FileUtils.chmod(0o000, @tmp_dir)

        _stdout, stderr = capture_io do
          writer.write_segment(Result.new(speaker: "A", text: "fail", start_time: 0.0, end_time: 1.0))
        end
        assert_includes stderr, "WARNING: JSONL write failed"
      ensure
        FileUtils.chmod(0o755, @tmp_dir)
      end
    end
  end
end
