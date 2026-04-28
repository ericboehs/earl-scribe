# frozen_string_literal: true

require "test_helper"
require "earl_scribe/cli/whisperkit_consolidate"

module EarlScribe
  module Cli
    class WhisperkitConsolidateTest < Minitest::Test
      def test_no_op_when_resemblyzer_unavailable
        Speaker::Encoder.stub(:available?, false) do
          remap = WhisperkitConsolidate.remap_labels(
            [{ start: 0, end: 5, speaker: "Speaker A" }], "/tmp/x.m4a"
          )
          assert_empty remap
        end
      end

      def test_no_op_on_empty_segments
        assert_empty WhisperkitConsolidate.remap_labels([], "/tmp/x.m4a")
      end

      def test_pick_representative_slice_takes_longest_per_speaker
        segments = [
          { start: 0, end: 2, speaker: "Speaker A" },
          { start: 5, end: 12, speaker: "Speaker A" }, # longer
          { start: 15, end: 18, speaker: "Speaker B" }
        ]
        slices = WhisperkitConsolidate.pick_representative_slice(segments)
        assert_equal 5, slices["Speaker A"][:start]
        assert_in_delta 9.0, slices["Speaker A"][:total_sec], 1e-6
        assert_equal 15, slices["Speaker B"][:start]
        assert_in_delta 3.0, slices["Speaker B"][:total_sec], 1e-6
      end

      def test_match_enrolled_relabels_when_identifier_matches
        identifier = Object.new
        identifier.define_singleton_method(:identify) do |emb|
          emb == [1, 0] ? ["Allison", 0.9] : [nil, 0.4]
        end
        embeddings = { "Speaker A" => [1, 0], "Speaker B" => [0, 1] }
        result = WhisperkitConsolidate.match_enrolled(embeddings, identifier)
        assert_equal({ "Speaker A" => "Allison" }, result)
      end

      def test_merge_unmatched_collapses_similar_clusters_to_larger
        embeddings = { "Speaker A" => [1.0, 0.0], "Speaker D" => [1.0, 0.001] }
        cluster_audio = {
          "Speaker A" => { start: 0, end: 10, total_sec: 10 },
          "Speaker D" => { start: 20, end: 22, total_sec: 2 }
        }
        merges = WhisperkitConsolidate.merge_unmatched(embeddings, {}, cluster_audio)
        assert_equal({ "Speaker D" => "Speaker A" }, merges)
      end

      def test_merge_unmatched_skips_dissimilar_clusters
        embeddings = { "Speaker A" => [1.0, 0.0], "Speaker B" => [0.0, 1.0] }
        cluster_audio = {
          "Speaker A" => { start: 0, end: 5, total_sec: 5 },
          "Speaker B" => { start: 5, end: 8, total_sec: 3 }
        }
        assert_empty WhisperkitConsolidate.merge_unmatched(embeddings, {}, cluster_audio)
      end

      def test_merge_unmatched_skips_already_enrolled
        embeddings = { "Speaker A" => [1.0, 0.0], "Speaker D" => [1.0, 0.001] }
        cluster_audio = {
          "Speaker A" => { start: 0, end: 10, total_sec: 10 },
          "Speaker D" => { start: 20, end: 22, total_sec: 2 }
        }
        enrolled = { "Speaker A" => "Allison" }
        assert_empty WhisperkitConsolidate.merge_unmatched(embeddings, enrolled, cluster_audio)
      end
    end
  end
end
