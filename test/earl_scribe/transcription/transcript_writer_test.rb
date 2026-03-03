# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Transcription
    class TranscriptWriterTest < Minitest::Test
      setup do
        @tmp_dir = Dir.mktmpdir("writer_test")
      end

      teardown do
        FileUtils.rm_rf(@tmp_dir)
      end

      test "build_paths returns txt path in data_dir" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          transcript, _recording = TranscriptWriter.build_paths(record: false)
          assert transcript.start_with?(@tmp_dir)
          assert transcript.end_with?(".txt")
        end
      end

      test "build_paths returns m4a when record is true" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          _transcript, recording = TranscriptWriter.build_paths(record: true)
          assert recording.end_with?(".m4a")
        end
      end

      test "build_paths returns nil recording when record is false" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          _transcript, recording = TranscriptWriter.build_paths(record: false)
          assert_nil recording
        end
      end

      test "build_paths uses same timestamp for both paths" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          transcript, recording = TranscriptWriter.build_paths(record: true)
          txt_base = File.basename(transcript, ".txt")
          m4a_base = File.basename(recording, ".m4a")
          assert_equal txt_base, m4a_base
        end
      end

      test "write_line writes to stdout and file" do
        path = File.join(@tmp_dir, "test.txt")
        writer = TranscriptWriter.new(path)

        stdout, _stderr = capture_io { writer.write_line("Hello world") }

        assert_includes stdout, "Hello world"
        assert_includes File.read(path), "Hello world"
        writer.close
      end

      test "write_line persists immediately" do
        path = File.join(@tmp_dir, "test.txt")
        writer = TranscriptWriter.new(path)

        capture_io { writer.write_line("Line 1") }
        content = File.read(path)
        assert_includes content, "Line 1"
        writer.close
      end

      test "creates parent directories" do
        path = File.join(@tmp_dir, "nested", "dir", "test.txt")
        writer = TranscriptWriter.new(path)
        capture_io { writer.write_line("nested") }

        assert File.exist?(path)
        writer.close
      end

      test "close is idempotent" do
        path = File.join(@tmp_dir, "test.txt")
        writer = TranscriptWriter.new(path)
        writer.close
        writer.close
      end

      test "write_line after close still prints to stdout but not file" do
        path = File.join(@tmp_dir, "test.txt")
        writer = TranscriptWriter.new(path)
        capture_io { writer.write_line("before") }
        writer.close
        stdout, _stderr = capture_io { writer.write_line("after") }

        assert_includes stdout, "after"
        content = File.read(path)
        assert_includes content, "before"
        assert_not_includes content, "after"
      end
    end
  end
end
