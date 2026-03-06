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

      test "build_paths returns hash with txt path in data_dir" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          paths = TranscriptWriter.build_paths(record: false)
          assert paths[:transcript].start_with?(@tmp_dir)
          assert paths[:transcript].end_with?(".txt")
        end
      end

      test "build_paths returns hash with jsonl path" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          paths = TranscriptWriter.build_paths(record: false)
          assert paths[:jsonl].end_with?(".jsonl")
        end
      end

      test "build_paths returns m4a when record is true" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          paths = TranscriptWriter.build_paths(record: true)
          assert paths[:recording].end_with?(".m4a")
        end
      end

      test "build_paths returns nil recording when record is false" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          paths = TranscriptWriter.build_paths(record: false)
          assert_nil paths[:recording]
        end
      end

      test "build_paths uses same timestamp for all paths" do
        EarlScribe.stub(:data_dir, @tmp_dir) do
          paths = TranscriptWriter.build_paths(record: true)
          txt_base = File.basename(paths[:transcript], ".txt")
          m4a_base = File.basename(paths[:recording], ".m4a")
          jsonl_base = File.basename(paths[:jsonl], ".jsonl")
          assert_equal txt_base, m4a_base
          assert_equal txt_base, jsonl_base
        end
      end

      test "write_line writes to file only" do
        path = File.join(@tmp_dir, "test.txt")
        writer = TranscriptWriter.new(path)

        stdout, _stderr = capture_io { writer.write_line("Hello world") }

        assert_equal "", stdout
        assert_includes File.read(path), "Hello world"
        writer.close
      end

      test "write_line persists immediately" do
        path = File.join(@tmp_dir, "test.txt")
        writer = TranscriptWriter.new(path)

        writer.write_line("Line 1")
        content = File.read(path)
        assert_includes content, "Line 1"
        writer.close
      end

      test "creates parent directories" do
        path = File.join(@tmp_dir, "nested", "dir", "test.txt")
        writer = TranscriptWriter.new(path)
        writer.write_line("nested")

        assert File.exist?(path)
        writer.close
      end

      test "close is idempotent" do
        path = File.join(@tmp_dir, "test.txt")
        writer = TranscriptWriter.new(path)
        writer.close
        writer.close
      end

      test "write_line after close does not write to file" do
        path = File.join(@tmp_dir, "test.txt")
        writer = TranscriptWriter.new(path)
        writer.write_line("before")
        writer.close
        writer.write_line("after")

        content = File.read(path)
        assert_includes content, "before"
        assert_not_includes content, "after"
      end
    end
  end
end
