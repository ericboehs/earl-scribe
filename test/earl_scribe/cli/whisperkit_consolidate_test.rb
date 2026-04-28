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

      def test_remap_labels_full_path_relabels_enrolled_and_merges_unmatched
        segments = [
          { start: 0, end: 5, speaker: "Speaker A" },     # enrolled (Allison)
          { start: 5, end: 10, speaker: "Speaker B" },    # too brief — but with multi-segment goes through
          { start: 10, end: 15, speaker: "Speaker C" },   # unmatched, but matches D
          { start: 15, end: 18, speaker: "Speaker D" }    # unmatched, matches C
        ]
        store = Object.new
        store.define_singleton_method(:list) { {} }
        # Stub encoder.encode to return distinct embeddings
        Speaker::Encoder.stub(:available?, true) do
          Audio::SegmentExtractor.stub(:extract_wav, ->(*args) { args.last[:output_path] }) do
            Speaker::Encoder.stub(:encode, lambda { |path|
              case File.basename(path)
              when /^Speaker_A-/ then [1.0, 0.0, 0.0]
              when /^Speaker_B-/ then [0.0, 1.0, 0.0]
              when /^Speaker_C-/, /^Speaker_D-/ then [0.0, 0.0, 1.0]
              end
            }) do
              identifier = Object.new
              identifier.define_singleton_method(:identify) do |emb|
                emb == [1.0, 0.0, 0.0] ? ["Allison", 0.9] : [nil, 0.4]
              end
              Speaker::Identifier.stub(:new, identifier) do
                remap = WhisperkitConsolidate.remap_labels(segments, "/tmp/x.m4a", store: store)
                assert_equal "Allison", remap["Speaker A"]
                # C and D have same embedding — one should merge into the other
                merge_pairs = remap.select { |_, v| v.start_with?("Speaker") }
                assert_equal 1, merge_pairs.size
              end
            end
          end
        end
      end

      def test_remap_labels_skips_clusters_below_min_total_sec
        segments = [
          { start: 0, end: 0.5, speaker: "Speaker A" } # 0.5s < 1.5s min
        ]
        Speaker::Encoder.stub(:available?, true) do
          remap = WhisperkitConsolidate.remap_labels(segments, "/tmp/x.m4a")
          assert_empty remap
        end
      end

      def test_average_embeddings_returns_nil_when_no_segments_extract
        Audio::SegmentExtractor.stub(:extract_wav, ->(*) { raise EarlScribe::Error, "ffmpeg failed" }) do
          Dir.mktmpdir do |dir|
            assert_raises(EarlScribe::Error) do
              WhisperkitConsolidate.average_embeddings("/tmp/x.m4a", dir, "Speaker A",
                                                       [{ start: 0, end: 5 }])
            end
          end
        end
      end

      def test_encode_clusters_logs_and_continues_on_failure
        clusters = { "Speaker A" => { top_segments: [{ start: 0, end: 5 }], total_sec: 5 } }
        Audio::SegmentExtractor.stub(:extract_wav, ->(*) { raise EarlScribe::Error, "boom" }) do
          # Should not raise — logger.warn captures the error
          result = WhisperkitConsolidate.encode_clusters("/tmp/x.m4a", clusters)
          assert_empty result
        end
      end

      def test_encode_clusters_skips_when_average_returns_nil
        # Two clusters; one extracts ok but encoder returns nil (embeddings.empty?)
        clusters = { "Speaker A" => { top_segments: [{ start: 0, end: 5 }], total_sec: 5 } }
        # Stub average_embeddings on the module to return nil
        WhisperkitConsolidate.stub(:average_embeddings, nil) do
          result = WhisperkitConsolidate.encode_clusters("/tmp/x.m4a", clusters)
          assert_empty result
        end
      end

      def test_smaller_handles_tied_total_sec
        clusters = { "A" => { total_sec: 5 }, "B" => { total_sec: 5 } }
        # Tied → returns "B" since strict-less is false
        assert_equal "B", WhisperkitConsolidate.smaller("A", "B", clusters)
      end

      def test_larger_picks_first_when_tied
        clusters = { "A" => { total_sec: 5 }, "B" => { total_sec: 5 } }
        # Tied → returns "A" since >= is true
        assert_equal "A", WhisperkitConsolidate.larger("A", "B", clusters)
      end

      def test_smaller_picks_first_when_first_is_smaller
        clusters = { "A" => { total_sec: 1 }, "B" => { total_sec: 9 } }
        assert_equal "A", WhisperkitConsolidate.smaller("A", "B", clusters)
      end

      def test_try_merge_pair_skips_when_speaker_already_merged
        embeddings = { "A" => [1.0, 0.0], "B" => [1.0, 0.0], "C" => [1.0, 0.0] }
        clusters = { "A" => { total_sec: 10 }, "B" => { total_sec: 5 }, "C" => { total_sec: 1 } }
        merges = WhisperkitConsolidate.merge_unmatched(embeddings, {}, clusters)
        # B and C both merge into A (largest); merges should not duplicate
        # Once B is in merges, C's pair vs B should skip
        assert_includes merges.keys, "B"
        assert_includes merges.keys, "C"
        assert_equal 2, merges.size
      end

      def test_average_embeddings_returns_nil_when_extracts_yield_nothing
        Audio::SegmentExtractor.stub(:extract_wav, ->(*) { raise EarlScribe::Error, "boom" }) do
          Dir.mktmpdir do |dir|
            assert_raises(EarlScribe::Error) do
              WhisperkitConsolidate.average_embeddings("/x.m4a", dir, "A", [{ start: 0, end: 5 }])
            end
          end
        end
      end

      def test_group_clusters_picks_top_segments_and_totals_duration
        segments = [
          { start: 0, end: 2, speaker: "Speaker A" },     # 2s
          { start: 5, end: 12, speaker: "Speaker A" },    # 7s — longest
          { start: 14, end: 17, speaker: "Speaker A" },   # 3s
          { start: 20, end: 21, speaker: "Speaker A" },   # 1s — should NOT be in top 3
          { start: 25, end: 28, speaker: "Speaker B" }    # 3s
        ]
        clusters = WhisperkitConsolidate.group_clusters(segments)
        assert_equal 3, clusters["Speaker A"][:top_segments].size
        assert_in_delta 13.0, clusters["Speaker A"][:total_sec], 1e-6
        top = clusters["Speaker A"][:top_segments].first
        assert_equal 7, top[:end] - top[:start]
        assert_in_delta 3.0, clusters["Speaker B"][:total_sec], 1e-6
      end

      def test_average_vectors_returns_input_when_one
        assert_equal [1.0, 2.0], WhisperkitConsolidate.average_vectors([[1.0, 2.0]])
      end

      def test_average_vectors_means_elementwise
        result = WhisperkitConsolidate.average_vectors([[1.0, 0.0], [3.0, 4.0]])
        assert_in_delta 2.0, result[0], 1e-6
        assert_in_delta 2.0, result[1], 1e-6
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
        clusters = {
          "Speaker A" => { total_sec: 10 },
          "Speaker D" => { total_sec: 2 }
        }
        merges = WhisperkitConsolidate.merge_unmatched(embeddings, {}, clusters)
        assert_equal({ "Speaker D" => "Speaker A" }, merges)
      end

      def test_merge_unmatched_skips_dissimilar_clusters
        embeddings = { "Speaker A" => [1.0, 0.0], "Speaker B" => [0.0, 1.0] }
        clusters = { "Speaker A" => { total_sec: 5 }, "Speaker B" => { total_sec: 3 } }
        assert_empty WhisperkitConsolidate.merge_unmatched(embeddings, {}, clusters)
      end

      def test_merge_unmatched_skips_already_enrolled
        embeddings = { "Speaker A" => [1.0, 0.0], "Speaker D" => [1.0, 0.001] }
        clusters = { "Speaker A" => { total_sec: 10 }, "Speaker D" => { total_sec: 2 } }
        enrolled = { "Speaker A" => "Allison" }
        assert_empty WhisperkitConsolidate.merge_unmatched(embeddings, enrolled, clusters)
      end
    end
  end
end
