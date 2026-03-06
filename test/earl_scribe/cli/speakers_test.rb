# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Cli
    class SpeakersTest < Minitest::Test
      setup { @tmpdir = Dir.mktmpdir("earl-scribe-test") }
      teardown { FileUtils.remove_entry(@tmpdir) }

      test "run shows usage for unknown subcommand" do
        _stdout, stderr = capture_io { EarlScribe::Cli::Speakers.run(["unknown"]) }
        assert_includes stderr, "Usage: earl-scribe speakers"
      end

      test "run shows usage for no arguments" do
        _stdout, stderr = capture_io { EarlScribe::Cli::Speakers.run([]) }
        assert_includes stderr, "Usage: earl-scribe speakers"
      end

      test "run_list with empty store" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        EarlScribe::Speaker::Store.stub(:new, store) do
          stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(["list"]) }
          assert_includes stdout, "No speakers enrolled"
        end
      end

      test "run_list with enrolled speakers" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        EarlScribe::Speaker::Store.stub(:new, store) do
          stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(["list"]) }
          assert_includes stdout, "Alice"
          assert_includes stdout, "Bob"
          assert_includes stdout, "1 sample"
        end
      end

      test "run_delete removes speaker" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        EarlScribe::Speaker::Store.stub(:new, store) do
          stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(%w[delete Alice]) }
          assert_includes stdout, "Deleted 'Alice'"
        end
        assert_not File.exist?(File.join(@tmpdir, "alice.json"))
      end

      test "run_delete aborts without name" do
        error = assert_raises(SystemExit) { EarlScribe::Cli::Speakers.run(["delete"]) }
        assert_equal 1, error.status
      end

      test "run_enroll aborts without name" do
        error = assert_raises(SystemExit) { EarlScribe::Cli::Speakers.run(["enroll"]) }
        assert_equal 1, error.status
      end

      test "run_enroll aborts without wav paths" do
        error = assert_raises(SystemExit) { EarlScribe::Cli::Speakers.run(%w[enroll TestName]) }
        assert_equal 1, error.status
      end

      test "run_enroll encodes and saves speaker" do
        wav_path = File.join(@tmpdir, "test.wav")
        File.write(wav_path, "fake audio")

        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        embedding = [0.1, 0.2, 0.3]

        EarlScribe::Speaker::Store.stub(:new, store) do
          EarlScribe::Speaker::Encoder.stub(:encode, embedding) do
            stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(["enroll", "TestSpeaker", wav_path]) }
            assert_includes stdout, "Enrolled 'TestSpeaker'"
            assert_includes stdout, "1 sample"
          end
        end

        saved = store.find("TestSpeaker")
        assert_not_nil saved
        assert_equal [embedding], saved["embeddings"]
      end

      test "run_enroll aborts when file not found" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        EarlScribe::Speaker::Store.stub(:new, store) do
          error = assert_raises(SystemExit) do
            EarlScribe::Cli::Speakers.run(["enroll", "Test", "/nonexistent.wav"])
          end
          assert_equal 1, error.status
        end
      end

      test "run_identify shows matched speaker" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        embedding = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]

        EarlScribe::Speaker::Store.stub(:new, store) do
          EarlScribe::Speaker::Encoder.stub(:encode, embedding) do
            stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(["identify", "test.wav"]) }
            assert_includes stdout, "Alice"
            assert_includes stdout, "similarity"
          end
        end
      end

      test "run_identify shows unknown when no match" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        identifier = EarlScribe::Speaker::Identifier.new(store: store, threshold: 0.999)
        embedding = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]

        EarlScribe::Speaker::Store.stub(:new, store) do
          EarlScribe::Speaker::Encoder.stub(:encode, embedding) do
            EarlScribe::Speaker::Identifier.stub(:new, identifier) do
              stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(["identify", "test.wav"]) }
              assert_includes stdout, "Unknown speaker"
            end
          end
        end
      end

      test "run_identify aborts without wav_path" do
        error = assert_raises(SystemExit) { EarlScribe::Cli::Speakers.run(["identify"]) }
        assert_equal 1, error.status
      end

      test "run_test shows similarity scores" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        embedding = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]

        EarlScribe::Speaker::Store.stub(:new, store) do
          EarlScribe::Speaker::Encoder.stub(:encode, embedding) do
            stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(["test", "test.wav"]) }
            assert_includes stdout, "Similarity scores"
            assert_includes stdout, "Alice"
            assert_includes stdout, "Bob"
          end
        end
      end

      test "run_test aborts without wav_path" do
        error = assert_raises(SystemExit) { EarlScribe::Cli::Speakers.run(["test"]) }
        assert_equal 1, error.status
      end

      test "run_test aborts when no speakers enrolled" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        embedding = [0.1, 0.2, 0.3]

        EarlScribe::Speaker::Store.stub(:new, store) do
          EarlScribe::Speaker::Encoder.stub(:encode, embedding) do
            error = assert_raises(SystemExit) { EarlScribe::Cli::Speakers.run(["test", "test.wav"]) }
            assert_equal 1, error.status
          end
        end
      end

      test "run_list pluralizes samples when count greater than one" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        store.save("TestUser", embeddings: [[0.1], [0.2]], samples: ["a.wav"])

        EarlScribe::Speaker::Store.stub(:new, store) do
          stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(["list"]) }
          assert_includes stdout, "2 samples"
        end
      end

      test "run dispatches learn subcommand" do
        learn_called = false
        EarlScribe::Cli::Learn.stub(:run, ->(_argv) { learn_called = true }) do
          EarlScribe::Cli::Speakers.run(["learn"])
        end
        assert learn_called
      end

      test "run_test marks MATCH for high similarity" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        embedding = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]

        EarlScribe::Speaker::Store.stub(:new, store) do
          EarlScribe::Speaker::Encoder.stub(:encode, embedding) do
            stdout, _stderr = capture_io { EarlScribe::Cli::Speakers.run(["test", "test.wav"]) }
            assert_includes stdout, "MATCH"
          end
        end
      end

      private

      def setup_fixture_speakers
        FileUtils.cp(fixture_path("speakers/alice.json"), @tmpdir)
        FileUtils.cp(fixture_path("speakers/bob.json"), @tmpdir)
      end
    end
  end
end
