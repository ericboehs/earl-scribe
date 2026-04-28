# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module EarlScribe
  module Cli
    # Consolidates whisperkit-cli's auto-detected diarization clusters using
    # resemblyzer embeddings. Two passes:
    #
    #   1. Match each auto-cluster against enrolled speakers — if a cluster's
    #      embedding cosine-matches an enrolled voiceprint above the
    #      Speaker::Identifier threshold, relabel it as that name.
    #
    #   2. Merge near-duplicate auto-clusters — for any two unmatched clusters
    #      whose embeddings cosine match >= MERGE_THRESHOLD, collapse the
    #      shorter-spoken one into the longer one.
    #
    # The result is a label remap (e.g. "Speaker A" -> "Allison",
    # "Speaker D" -> "Speaker A") applied to RTTM segments before splicing.
    # No-op when resemblyzer isn't available; falls back to raw labels.
    module WhisperkitConsolidate
      module_function

      MERGE_THRESHOLD = 0.85
      # Minimum total audio per cluster — sum across the top SEGMENTS_PER_CLUSTER
      # longest segments. Anything below this is too little signal for resemblyzer.
      MIN_TOTAL_SEC = 1.5
      SEGMENTS_PER_CLUSTER = 3

      def remap_labels(rttm_segments, audio_path, store: nil)
        return {} if rttm_segments.empty? || !Speaker::Encoder.available?

        store ||= Speaker::Store.new
        clusters = group_clusters(rttm_segments)
        embeddings = encode_clusters(audio_path, clusters)
        return {} if embeddings.empty?

        identifier = Speaker::Identifier.new(store: store)
        enrolled = match_enrolled(embeddings, identifier)
        merged = merge_unmatched(embeddings, enrolled, clusters)
        enrolled.merge(merged)
      end

      def group_clusters(rttm_segments)
        rttm_segments.group_by { |s| s[:speaker] }
                     .transform_values { |segs| cluster_info(segs) }
      end

      def cluster_info(segs)
        sorted = segs.sort_by { |s| -(s[:end] - s[:start]) }
        top = sorted.first(SEGMENTS_PER_CLUSTER)
        { top_segments: top, total_sec: segs.sum { |s| s[:end] - s[:start] } }
      end

      # Encode each cluster by averaging embeddings across the top N longest
      # segments. Brief clusters that don't accumulate MIN_TOTAL_SEC across
      # those segments get skipped (too little signal for a stable embedding).
      def encode_clusters(audio_path, clusters)
        Dir.mktmpdir("wk-consolidate-") do |dir|
          clusters.each_with_object({}) do |(speaker, info), embeddings|
            sliced = top_seconds(info[:top_segments])
            next if sliced < MIN_TOTAL_SEC

            embedding = average_embeddings(audio_path, dir, speaker, info[:top_segments])
            embeddings[speaker] = embedding if embedding
          rescue Error => error
            EarlScribe.logger.warn("encode failed for #{speaker}: #{error.message}")
          end
        end
      end

      def top_seconds(segments)
        segments.sum { |s| s[:end] - s[:start] }
      end

      def average_embeddings(audio_path, dir, speaker, segments)
        slug = speaker.tr(" ", "_")
        embeddings = segments.each_with_index.filter_map do |seg, idx|
          wav = File.join(dir, "#{slug}-#{idx}.wav")
          Audio::SegmentExtractor.extract_wav(audio_path, seg[:start], seg[:end], output_path: wav)
          Speaker::Encoder.encode(wav)
        end
        return nil if embeddings.empty?

        average_vectors(embeddings)
      end

      def average_vectors(vectors)
        return vectors.first if vectors.size == 1

        size = vectors.first.size
        sums = Array.new(size, 0.0)
        vectors.each { |v| size.times { |i| sums[i] += v[i] } }
        sums.map { |s| s / vectors.size.to_f }
      end

      def match_enrolled(embeddings, identifier)
        embeddings.each_with_object({}) do |(speaker, emb), out|
          name, _sim = identifier.identify(emb)
          out[speaker] = name if name
        end
      end

      def merge_unmatched(embeddings, enrolled, clusters)
        unmatched = embeddings.reject { |k, _| enrolled.key?(k) }.to_a
        merges = {}
        unmatched.each_with_index do |(speaker_a, emb_a), i|
          unmatched.drop(i + 1).each do |speaker_b, emb_b|
            next if merges.key?(speaker_b) || merges.key?(speaker_a)
            next if Speaker::VectorMath.cosine_similarity(emb_a, emb_b) < MERGE_THRESHOLD

            merges[smaller(speaker_a, speaker_b, clusters)] = larger(speaker_a, speaker_b, clusters)
          end
        end
        merges
      end

      def smaller(speaker_a, speaker_b, clusters)
        clusters[speaker_a][:total_sec] < clusters[speaker_b][:total_sec] ? speaker_a : speaker_b
      end

      def larger(speaker_a, speaker_b, clusters)
        clusters[speaker_a][:total_sec] >= clusters[speaker_b][:total_sec] ? speaker_a : speaker_b
      end
    end
  end
end
