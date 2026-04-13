# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Audio
    class ChunkPollerTest < Minitest::Test
      test "poll yields completed chunks but not the last in-progress one" do
        Dir.mktmpdir("poller_test") do |tmp_dir|
          poller = ChunkPoller.new(tmp_dir)
          wav1 = File.join(tmp_dir, "20260302_100000.wav")
          wav2 = File.join(tmp_dir, "20260302_100010.wav")
          File.write(wav1, "complete")
          File.write(wav2, "in progress")

          yielded = []
          poller.define_singleton_method(:sleep) { |_| raise StopIteration }

          begin
            poller.poll { |path| yielded << path }
          rescue StopIteration
            nil
          end

          assert_equal [wav1], yielded
        end
      end

      test "poll skips zero-byte files" do
        Dir.mktmpdir("poller_test") do |tmp_dir|
          poller = ChunkPoller.new(tmp_dir)
          empty = File.join(tmp_dir, "20260302_100000.wav")
          good = File.join(tmp_dir, "20260302_100010.wav")
          later = File.join(tmp_dir, "20260302_100020.wav")
          File.write(empty, "")
          File.write(good, "audio")
          File.write(later, "later")

          yielded = []
          poller.define_singleton_method(:sleep) { |_| raise StopIteration }

          begin
            poller.poll { |path| yielded << path }
          rescue StopIteration
            nil
          end

          assert_equal [good], yielded
        end
      end

      test "poll does not re-yield files already yielded" do
        Dir.mktmpdir("poller_test") do |tmp_dir|
          poller = ChunkPoller.new(tmp_dir)
          wav1 = File.join(tmp_dir, "20260302_100000.wav")
          wav2 = File.join(tmp_dir, "20260302_100010.wav")
          File.write(wav1, "audio 1")
          File.write(wav2, "audio 2")

          yielded = []
          call_count = 0
          poller.define_singleton_method(:sleep) do |_|
            call_count += 1
            raise StopIteration if call_count >= 2
          end

          begin
            poller.poll { |path| yielded << path }
          rescue StopIteration
            nil
          end

          assert_equal [wav1], yielded
        end
      end

      test "yield_final_chunk yields unflushed files with content" do
        Dir.mktmpdir("poller_test") do |tmp_dir|
          poller = ChunkPoller.new(tmp_dir)
          wav1 = File.join(tmp_dir, "20260302_100000.wav")
          wav2 = File.join(tmp_dir, "20260302_100010.wav")
          File.write(wav1, "audio 1")
          File.write(wav2, "audio 2")

          yielded = []
          poller.yield_final_chunk { |path| yielded << path }

          assert_equal [wav1, wav2], yielded
        end
      end

      test "yield_final_chunk skips already-yielded files" do
        Dir.mktmpdir("poller_test") do |tmp_dir|
          poller = ChunkPoller.new(tmp_dir)
          wav1 = File.join(tmp_dir, "20260302_100000.wav")
          File.write(wav1, "audio")
          poller.instance_variable_get(:@yielded).add(wav1)

          yielded = []
          poller.yield_final_chunk { |path| yielded << path }

          assert_empty yielded
        end
      end

      test "yield_final_chunk skips zero-byte files" do
        Dir.mktmpdir("poller_test") do |tmp_dir|
          poller = ChunkPoller.new(tmp_dir)
          empty = File.join(tmp_dir, "20260302_100000.wav")
          File.write(empty, "")

          yielded = []
          poller.yield_final_chunk { |path| yielded << path }

          assert_empty yielded
        end
      end
    end
  end
end
