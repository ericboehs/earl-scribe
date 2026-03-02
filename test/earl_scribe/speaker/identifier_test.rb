# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Speaker
    class IdentifierTest < Minitest::Test
      setup { @tmpdir = Dir.mktmpdir("earl-scribe-test") }
      teardown { FileUtils.remove_entry(@tmpdir) }

      test "identifies matching speaker above threshold" do
        setup_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        identifier = EarlScribe::Speaker::Identifier.new(store: store)

        # Embedding very similar to Alice [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
        embedding = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
        name, similarity = identifier.identify(embedding)

        assert_equal "Alice", name
        assert_in_delta 1.0, similarity, 0.01
      end

      test "returns nil when below threshold" do
        setup_speakers
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        identifier = EarlScribe::Speaker::Identifier.new(store: store, threshold: 0.99)

        # Embedding somewhat between Alice and Bob
        embedding = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
        name, _similarity = identifier.identify(embedding)

        assert_nil name
      end

      test "returns nil and zero when no speakers enrolled" do
        store = EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        identifier = EarlScribe::Speaker::Identifier.new(store: store)

        name, similarity = identifier.identify([0.1, 0.2, 0.3])

        assert_nil name
        assert_in_delta 0.0, similarity
      end

      test "custom threshold is respected" do
        identifier = EarlScribe::Speaker::Identifier.new(
          store: EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir),
          threshold: 0.5
        )
        assert_in_delta 0.5, identifier.threshold
      end

      test "default threshold is 0.75" do
        identifier = EarlScribe::Speaker::Identifier.new(
          store: EarlScribe::Speaker::Store.new(speakers_dir: @tmpdir)
        )
        assert_in_delta 0.75, identifier.threshold
      end

      private

      def setup_speakers
        FileUtils.cp(fixture_path("speakers/alice.json"), @tmpdir)
        FileUtils.cp(fixture_path("speakers/bob.json"), @tmpdir)
      end
    end
  end
end
