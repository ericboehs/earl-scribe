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
      MIN_SLICE_SEC = 1.5

      def remap_labels(rttm_segments, audio_path, store: nil)
        return {} if rttm_segments.empty? || !Speaker::Encoder.available?

        store ||= Speaker::Store.new
        cluster_audio = pick_representative_slice(rttm_segments)
        embeddings = encode_clusters(audio_path, cluster_audio)
        return {} if embeddings.empty?

        identifier = Speaker::Identifier.new(store: store)
        enrolled = match_enrolled(embeddings, identifier)
        merged = merge_unmatched(embeddings, enrolled, cluster_audio)
        enrolled.merge(merged)
      end

      def pick_representative_slice(rttm_segments)
        durations = rttm_segments.group_by { |s| s[:speaker] }
                                 .transform_values { |segs| segs.sum { |s| s[:end] - s[:start] } }
        rttm_segments.group_by { |s| s[:speaker] }
                     .to_h { |speaker, segs| [speaker, longest(segs).merge(total_sec: durations[speaker])] }
      end

      def longest(segs)
        segs.max_by { |s| s[:end] - s[:start] }
      end

      def encode_clusters(audio_path, cluster_audio)
        Dir.mktmpdir("wk-consolidate-") do |dir|
          cluster_audio.each_with_object({}) do |(speaker, slice), embeddings|
            duration = slice[:end] - slice[:start]
            next if duration < MIN_SLICE_SEC

            wav = File.join(dir, "#{speaker.tr(" ", "_")}.wav")
            Audio::SegmentExtractor.extract_wav(audio_path, slice[:start], slice[:end], output_path: wav)
            embeddings[speaker] = Speaker::Encoder.encode(wav)
          rescue Error => error
            EarlScribe.logger.warn("encode failed for #{speaker}: #{error.message}")
          end
        end
      end

      def match_enrolled(embeddings, identifier)
        embeddings.each_with_object({}) do |(speaker, emb), out|
          name, _sim = identifier.identify(emb)
          out[speaker] = name if name
        end
      end

      def merge_unmatched(embeddings, enrolled, cluster_audio)
        unmatched = embeddings.reject { |k, _| enrolled.key?(k) }.to_a
        merges = {}
        unmatched.each_with_index do |(speaker_a, emb_a), i|
          unmatched.drop(i + 1).each do |speaker_b, emb_b|
            next if merges.key?(speaker_b) || merges.key?(speaker_a)
            next if Speaker::VectorMath.cosine_similarity(emb_a, emb_b) < MERGE_THRESHOLD

            merges[smaller(speaker_a, speaker_b, cluster_audio)] = larger(speaker_a, speaker_b, cluster_audio)
          end
        end
        merges
      end

      def smaller(speaker_a, speaker_b, cluster_audio)
        cluster_audio[speaker_a][:total_sec] < cluster_audio[speaker_b][:total_sec] ? speaker_a : speaker_b
      end

      def larger(speaker_a, speaker_b, cluster_audio)
        cluster_audio[speaker_a][:total_sec] >= cluster_audio[speaker_b][:total_sec] ? speaker_a : speaker_b
      end
    end
  end
end
