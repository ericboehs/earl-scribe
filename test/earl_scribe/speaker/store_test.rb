# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "json"

module EarlScribe
  module Speaker
    class StoreTest < Minitest::Test
      setup { @tmpdir = Dir.mktmpdir("earl-scribe-test") }
      teardown { FileUtils.remove_entry(@tmpdir) }

      test "list returns empty hash when dir does not exist" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: File.join(@tmpdir, "nonexistent"))
        assert_equal({}, store.list)
      end

      test "list returns speakers from json files" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        speakers = store.list

        assert_equal 2, speakers.size
        assert speakers.key?("Alice")
        assert speakers.key?("Bob")
      end

      test "find returns speaker data" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)

        alice = store.find("Alice")
        assert_equal "Alice", alice["name"]
        assert_equal 1, alice["embeddings"].size
      end

      test "find returns nil when not found" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        assert_nil store.find("Unknown")
      end

      test "save creates json file" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        store.save("Charlie", embeddings: [[0.1, 0.2]], samples: ["/tmp/c.wav"])

        path = File.join(@tmpdir, "charlie.json")
        assert File.exist?(path)
        data = JSON.parse(File.read(path))
        assert_equal "Charlie", data["name"]
        assert_equal [[0.1, 0.2]], data["embeddings"]
      end

      test "save creates directory if needed" do
        nested_dir = File.join(@tmpdir, "sub", "speakers")
        store = EarlScribe::Speaker::Store.new(speakers_dir: nested_dir)
        store.save("Test", embeddings: [[1.0]])

        assert Dir.exist?(nested_dir)
      end

      test "save uses safe filename" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        store.save("John Doe", embeddings: [[0.5]])

        assert File.exist?(File.join(@tmpdir, "john_doe.json"))
      end

      test "delete removes file" do
        setup_fixture_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        store.delete("Alice")

        assert_not File.exist?(File.join(@tmpdir, "alice.json"))
      end

      test "delete raises when speaker not found" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        error = assert_raises(EarlScribe::Error) { store.delete("Nobody") }
        assert_includes error.message, "Nobody"
      end

      test "speakers_dir defaults to config_root" do
        store = EarlScribe::Speaker::Store.new
        expected = File.join(EarlScribe.config_root, "speakers")
        assert_equal expected, store.speakers_dir
      end

      private

      def setup_fixture_speakers
        FileUtils.cp(fixture_path("speakers/alice.json"), @tmpdir)
        FileUtils.cp(fixture_path("speakers/bob.json"), @tmpdir)
      end
    end
  end
end
