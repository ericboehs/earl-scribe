# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

module EarlScribe
  module Cli
    class LearnTest < Minitest::Test
      setup do
        @data_dir = Dir.mktmpdir("learn_test")
        @speakers_dir = Dir.mktmpdir("learn_speakers")
      end

      teardown do
        FileUtils.rm_rf(@data_dir)
        FileUtils.rm_rf(@speakers_dir)
      end

      test "run prints message when no recordings found" do
        EarlScribe.stub(:data_dir, @data_dir) do
          stdout, _stderr = capture_io { Learn.run([]) }
          assert_includes stdout, "No recordings with unidentified speakers found"
        end
      end

      test "run skips jsonl without matching m4a" do
        write_test_jsonl
        EarlScribe.stub(:data_dir, @data_dir) do
          stdout, _stderr = capture_io { Learn.run([]) }
          assert_includes stdout, "No recordings with unidentified speakers found"
        end
      end

      test "run skips recordings where all speakers are identified" do
        path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        lines = [
          '{"type":"metadata","recorded_at":"now","meeting_title":"Test"}',
          '{"speaker":"Alice","text":"hello","start_time":0,"end_time":3,"channel":0}'
        ]
        File.write(path, "#{lines.join("\n")}\n")
        File.write(File.join(@data_dir, "earl-scribe-20260303_130000.m4a"), "fake")

        EarlScribe.stub(:data_dir, @data_dir) do
          stdout, _stderr = capture_io { Learn.run([]) }
          assert_includes stdout, "No recordings with unidentified speakers found"
        end
      end

      test "run processes recording and prompts for speaker names" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)

        run_learn_with_stubs(store: store, stdin_text: "Alice\nBob\n") do |stdout|
          assert_includes stdout, "EERT Standup"
          assert_includes stdout, "Who is Speaker 0?"
          assert_includes stdout, "Enrolled Alice"
        end
      end

      test "run auto-confirms high-similarity match" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        store.save("Alice", embeddings: [[0.1, 0.2, 0.3]], samples: [])

        identifier = Speaker::Identifier.new(store: store, threshold: 0.75)

        run_learn_with_stubs(store: store, identifier: identifier, stdin_text: "s\n") do |stdout|
          assert_includes stdout, "Auto-identified Speaker 0 as Alice"
        end
      end

      test "auto-identified speaker skips playback" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        store.save("Alice", embeddings: [[0.1, 0.2, 0.3]], samples: [])

        identifier = Speaker::Identifier.new(store: store, threshold: 0.75)
        play_called = false
        play_stub = ->(*_args) { play_called = true }

        EarlScribe.stub(:data_dir, @data_dir) do
          Speaker::Store.stub(:new, store) do
            Speaker::Identifier.stub(:new, identifier) do
              Speaker::Encoder.stub(:encode, ->(_p) { [0.1, 0.2, 0.3] }) do
                status = Minitest::Mock.new
                10.times { status.expect(:success?, true) }
                Open3.stub(:capture3, ->(*_args) { ["", "", status] }) do
                  Audio::Player.stub(:play_segment, play_stub) do
                    $stdin = StringIO.new("s\n")
                    stdout, _stderr = capture_io { Learn.run([]) }
                    assert_includes stdout, "Auto-identified Speaker 0 as Alice"
                    assert_not play_called, "play_segment should not be called for auto-identified speakers"
                  ensure
                    $stdin = STDIN
                  end
                end
              end
            end
          end
        end
      end

      test "speaker below auto-threshold still plays clips and prompts" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        store.save("Alice", embeddings: [[0.5, 0.5, 0.5]], samples: [])

        play_called = false
        play_stub = ->(*_args) { play_called = true }

        EarlScribe.stub(:data_dir, @data_dir) do
          Speaker::Store.stub(:new, store) do
            Speaker::Identifier.stub(:new, build_suggest_identifier) do
              Speaker::Encoder.stub(:encode, ->(_p) { [0.1, 0.2, 0.3] }) do
                status = Minitest::Mock.new
                10.times { status.expect(:success?, true) }
                Open3.stub(:capture3, ->(*_args) { ["", "", status] }) do
                  Audio::Player.stub(:play_segment, play_stub) do
                    $stdin = StringIO.new("y\ns\n")
                    stdout, _stderr = capture_io { Learn.run([]) }
                    assert_includes stdout, "Suggested: Alice"
                    assert play_called, "play_segment should be called for non-auto-identified speakers"
                  ensure
                    $stdin = STDIN
                  end
                end
              end
            end
          end
        end
      end

      test "run suggests match above threshold and accepts on Y" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        store.save("Alice", embeddings: [[0.5, 0.5, 0.5]], samples: [])

        run_learn_with_stubs(store: store, identifier: build_suggest_identifier, stdin_text: "y\ns\n") do |stdout|
          assert_includes stdout, "Suggested: Alice"
          assert_includes stdout, "Enrolled Alice"
        end
      end

      test "run suggests match and accepts custom name" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        store.save("Alice", embeddings: [[0.5, 0.5, 0.5]], samples: [])

        run_learn_with_stubs(store: store, identifier: build_suggest_identifier, stdin_text: "Bob\ns\n") do |stdout|
          assert_includes stdout, "Suggested: Alice"
          assert_includes stdout, "Enrolled Bob"
        end
      end

      test "run suggests match and rejects with n" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        store.save("Alice", embeddings: [[0.5, 0.5, 0.5]], samples: [])

        run_learn_with_stubs(store: store, identifier: build_suggest_identifier, stdin_text: "n\ns\n") do |stdout|
          assert_includes stdout, "Suggested: Alice"
          assert_not_includes stdout, "Enrolled Alice"
        end
      end

      test "run skips speaker when user enters s" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)

        run_learn_with_stubs(store: store, stdin_text: "s\ns\n") do |stdout|
          assert_includes stdout, "Who is Speaker 0?"
          assert_not_includes stdout, "Enrolled"
        end
      end

      test "run uses untitled recording and unknown date when metadata missing" do
        path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        lines = [
          '{"type":"metadata"}',
          '{"speaker":"Speaker 0","text":"Hello everyone","start_time":1.0,"end_time":4.5,"channel":0}'
        ]
        File.write(path, "#{lines.join("\n")}\n")
        write_test_m4a
        write_test_txt
        store = Speaker::Store.new(speakers_dir: @speakers_dir)

        run_learn_with_stubs(store: store, stdin_text: "s\n") do |stdout|
          assert_includes stdout, "Untitled Recording"
          assert_includes stdout, "Unknown date"
        end
      end

      test "run rewrites jsonl and txt after enrollment" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)

        run_learn_with_stubs(store: store, stdin_text: "Alice\nBob\n") do |stdout|
          assert_includes stdout, "Updated transcript files"
        end

        jsonl_path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        assert_includes File.read(jsonl_path), '"Alice"'

        txt_path = File.join(@data_dir, "earl-scribe-20260303_130000.txt")
        assert_includes File.read(txt_path), "Alice:"
      end

      test "run handles empty clips gracefully" do
        path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        lines = [
          '{"type":"metadata","recorded_at":"now","meeting_title":"Test"}',
          '{"speaker":"Speaker 0","text":"hi","start_time":0,"end_time":0.5,"channel":0}'
        ]
        File.write(path, "#{lines.join("\n")}\n")
        write_test_m4a
        store = Speaker::Store.new(speakers_dir: @speakers_dir)

        EarlScribe.stub(:data_dir, @data_dir) do
          Speaker::Store.stub(:new, store) do
            stdout, _stderr = capture_io { Learn.run([]) }
            assert_not_includes stdout, "Who is Speaker"
          end
        end
      end

      test "run averages multiple embeddings for a speaker with many segments" do
        path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        lines = [
          '{"type":"metadata","recorded_at":"now","meeting_title":"Test"}',
          '{"speaker":"Speaker 0","text":"Hello everyone","start_time":1.0,"end_time":4.5,"channel":0}',
          '{"speaker":"Speaker 0","text":"Another long segment","start_time":10.0,"end_time":14.0,"channel":0}'
        ]
        File.write(path, "#{lines.join("\n")}\n")
        write_test_m4a
        write_test_txt
        store = Speaker::Store.new(speakers_dir: @speakers_dir)

        run_learn_with_stubs(store: store, stdin_text: "Alice\n") do |stdout|
          assert_includes stdout, "Enrolled Alice"
        end
      end

      test "run handles EOF on suggestion prompt" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        store.save("Alice", embeddings: [[0.5, 0.5, 0.5]], samples: [])

        run_learn_with_stubs(store: store, identifier: build_suggest_identifier, stdin_text: "") do |stdout|
          assert_includes stdout, "Suggested: Alice"
          assert_includes stdout, "Enrolled Alice"
        end
      end

      test "suggest accepts empty input as yes" do
        setup_test_files
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        store.save("Alice", embeddings: [[0.5, 0.5, 0.5]], samples: [])

        run_learn_with_stubs(store: store, identifier: build_suggest_identifier, stdin_text: "\ns\n") do |stdout|
          assert_includes stdout, "Enrolled Alice"
        end
      end

      test "filter_outliers keeps all 3 clips when similarity is high" do
        setup_test_files_single_speaker
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        # All identical embeddings → high similarity → no outlier detected
        run_learn_with_stubs(store: store, stdin_text: "Alice\n") do |stdout|
          assert_not_includes stdout, "low similarity"
          assert_not_includes stdout, "Exclude?"
          assert_includes stdout, "Enrolled Alice"
        end
      end

      test "filter_outliers detects outlier and excludes on confirm" do
        setup_test_files_single_speaker
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        call_count = 0
        encode_stub = lambda do |_path|
          call_count += 1
          case call_count
          when 1 then [1.0, 0.0, 0.0]
          when 2 then [0.99, 0.05, 0.0]
          else [0.0, 0.0, 1.0] # outlier: orthogonal to the others
          end
        end

        run_learn_with_stubs(store: store, encode_stub: encode_stub, stdin_text: "y\nAlice\n") do |stdout|
          assert_includes stdout, "Exclude?"
          assert_includes stdout, "Enrolled Alice"
        end
      end

      test "filter_outliers keeps outlier when user declines exclusion" do
        setup_test_files_single_speaker
        store = Speaker::Store.new(speakers_dir: @speakers_dir)
        call_count = 0
        encode_stub = lambda do |_path|
          call_count += 1
          case call_count
          when 1 then [1.0, 0.0, 0.0]
          when 2 then [0.99, 0.05, 0.0]
          else [0.0, 0.0, 1.0]
          end
        end

        run_learn_with_stubs(store: store, encode_stub: encode_stub, stdin_text: "n\nAlice\n") do |stdout|
          assert_includes stdout, "Exclude?"
          assert_includes stdout, "Enrolled Alice"
        end
      end

      test "filter_outliers warns on low similarity with only 2 clips" do
        path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        lines = [
          '{"type":"metadata","recorded_at":"now","meeting_title":"Test"}',
          '{"speaker":"Speaker 0","text":"Hello everyone how are you","start_time":1.0,"end_time":4.5,"channel":0}',
          '{"speaker":"Speaker 0","text":"Another long segment here","start_time":10.0,"end_time":14.0,"channel":0}'
        ]
        File.write(path, "#{lines.join("\n")}\n")
        write_test_m4a
        write_test_txt
        store = Speaker::Store.new(speakers_dir: @speakers_dir)

        call_count = 0
        encode_stub = lambda do |_path|
          call_count += 1
          call_count == 1 ? [1.0, 0.0, 0.0] : [0.0, 0.0, 1.0]
        end

        run_learn_with_stubs(store: store, encode_stub: encode_stub, stdin_text: "Alice\n") do |stdout|
          assert_includes stdout, "Warning: low similarity"
          assert_not_includes stdout, "Exclude?"
        end
      end

      test "filter_outliers skips filtering with only 1 clip" do
        path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        lines = [
          '{"type":"metadata","recorded_at":"now","meeting_title":"Test"}',
          '{"speaker":"Speaker 0","text":"Hello everyone how are you","start_time":1.0,"end_time":4.5,"channel":0}'
        ]
        File.write(path, "#{lines.join("\n")}\n")
        write_test_m4a
        write_test_txt
        store = Speaker::Store.new(speakers_dir: @speakers_dir)

        run_learn_with_stubs(store: store, stdin_text: "Alice\n") do |stdout|
          assert_not_includes stdout, "low similarity"
          assert_not_includes stdout, "Exclude?"
          assert_includes stdout, "Enrolled Alice"
        end
      end

      private

      def setup_test_files
        write_test_jsonl
        write_test_m4a
        write_test_txt
      end

      def write_test_jsonl
        path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        lines = [
          '{"type":"metadata","recorded_at":"2026-03-03T13:00:00-06:00","meeting_title":"EERT Standup"}',
          '{"speaker":"Speaker 0","text":"Hello everyone","start_time":1.0,"end_time":4.5,"channel":0}',
          '{"speaker":"Speaker 1","text":"Hey there how are you","start_time":5.0,"end_time":9.0,"channel":0}'
        ]
        File.write(path, "#{lines.join("\n")}\n")
      end

      def write_test_m4a
        File.write(File.join(@data_dir, "earl-scribe-20260303_130000.m4a"), "fake audio")
      end

      def write_test_txt
        File.write(File.join(@data_dir, "earl-scribe-20260303_130000.txt"), "Speaker 0: Hello\n")
      end

      def setup_test_files_single_speaker
        path = File.join(@data_dir, "earl-scribe-20260303_130000.jsonl")
        lines = [
          '{"type":"metadata","recorded_at":"now","meeting_title":"Test"}',
          '{"speaker":"Speaker 0","text":"Hello everyone how are you","start_time":1.0,"end_time":4.5,"channel":0}',
          '{"speaker":"Speaker 0","text":"Another segment for testing","start_time":10.0,"end_time":14.0,"channel":0}',
          '{"speaker":"Speaker 0","text":"A third segment with words","start_time":20.0,"end_time":24.0,"channel":0}'
        ]
        File.write(path, "#{lines.join("\n")}\n")
        write_test_m4a
        write_test_txt
      end

      def stub_playback(&block)
        Audio::Player.stub(:play_segment, nil, &block)
      end

      def build_suggest_identifier
        identifier = Object.new
        identifier.define_singleton_method(:identify) { |_embedding| ["Alice", 0.80] }
        identifier
      end

      def run_learn_with_stubs(store:, identifier: nil, encode_stub: nil, stdin_text: "s\n")
        status = Minitest::Mock.new
        10.times { status.expect(:success?, true) }
        encode_stub ||= ->(_p) { [0.1, 0.2, 0.3] }

        EarlScribe.stub(:data_dir, @data_dir) do
          Speaker::Store.stub(:new, store) do
            id_stub = identifier || Speaker::Identifier.new(store: store)
            Speaker::Identifier.stub(:new, id_stub) do
              Speaker::Encoder.stub(:encode, encode_stub) do
                Open3.stub(:capture3, ->(*_args) { ["", "", status] }) do
                  stub_playback do
                    $stdin = StringIO.new(stdin_text)
                    stdout, _stderr = capture_io { Learn.run([]) }
                    yield stdout if block_given?
                  ensure
                    $stdin = STDIN
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
