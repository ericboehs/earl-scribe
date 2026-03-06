# frozen_string_literal: true

require "tmpdir"
require_relative "learn_prompter"
require_relative "learn_rewriter"

module EarlScribe
  module Cli
    # Interactive speaker enrollment from past meeting recordings
    module Learn
      OUTLIER_THRESHOLD = 0.75

      def self.run(_argv)
        recordings = scan_recordings
        if recordings.empty?
          puts "No recordings with unidentified speakers found."
          return
        end

        recordings.each { |rec| process_recording(rec) }
      end

      def self.scan_recordings
        Dir.glob(File.join(EarlScribe.data_dir, "*.jsonl")).filter_map do |jsonl_path|
          build_recording_entry(jsonl_path)
        end
      end

      def self.build_recording_entry(jsonl_path)
        m4a_path = jsonl_path.sub(/\.jsonl\z/, ".m4a")
        return unless File.exist?(m4a_path)

        reader = Transcription::JsonlReader.new(jsonl_path)
        return unless reader.unidentified_speakers?

        { jsonl_path: jsonl_path, m4a_path: m4a_path, reader: reader }
      end

      def self.process_recording(rec)
        print_recording_header(rec[:reader])
        store = Speaker::Store.new
        identifier = Speaker::Identifier.new(store: store)
        updates = collect_updates(rec, identifier, store)
        LearnRewriter.rewrite(rec, updates) unless updates.empty?
      end

      def self.collect_updates(rec, identifier, store)
        rec[:reader].unidentified_speakers.each_with_object({}) do |label, updates|
          name = learn_speaker(label, rec, identifier, store)
          updates[label] = name if name
        end
      end

      def self.print_recording_header(reader)
        title = reader.meeting_title || "Untitled Recording"
        date = reader.recorded_at || "Unknown date"
        puts "\n--- #{title} (#{date}) ---"
      end

      def self.learn_speaker(label, rec, identifier, store)
        segments = rec[:reader].segments_for_speaker(label)
        Dir.mktmpdir("earl-learn") do |tmp_dir|
          clips = Audio::SegmentExtractor.extract_best_segments(rec[:m4a_path], segments, tmp_dir: tmp_dir)
          next if clips.empty?

          embeddings = encode_clips(clips)
          _clips, embeddings = filter_outliers(clips, embeddings)
          next if embeddings.empty?

          LearnPrompter.resolve_identity(label, embeddings, identifier, store) { play_clips(clips, rec[:m4a_path]) }
        end
      end

      def self.play_clips(clips, m4a_path)
        clips.each do |clip|
          seg = clip[:segment]
          puts "  Playing: \"#{seg.text}\" (Enter to skip)"
          Audio::Player.play_segment(m4a_path, seg.start_time, seg.end_time)
        end
      end

      def self.encode_clips(clips)
        clips.map { |clip| Speaker::Encoder.encode(clip[:wav_path]) }
      end

      def self.filter_outliers(clips, embeddings)
        return [clips, embeddings] if embeddings.size < 2

        if embeddings.size == 2
          warn_low_pair_similarity(embeddings)
          return [clips, embeddings]
        end

        exclude_outlier(clips, embeddings)
      end

      def self.warn_low_pair_similarity(embeddings)
        sim = Speaker::VectorMath.cosine_similarity(embeddings[0], embeddings[1])
        puts "  Warning: low similarity between clips (#{sim.round(2)})" if sim < OUTLIER_THRESHOLD
      end

      def self.exclude_outlier(clips, embeddings)
        outlier_idx, avg_sim = find_outlier(embeddings)
        return [clips, embeddings] unless outlier_idx
        return [clips, embeddings] unless confirm_exclusion?(clips[outlier_idx], avg_sim)

        [clips.dup.tap { |c| c.delete_at(outlier_idx) }, embeddings.dup.tap { |e| e.delete_at(outlier_idx) }]
      end

      def self.find_outlier(embeddings)
        avg_sims = embeddings.each_with_index.map do |emb, i|
          others = embeddings.each_with_index.reject { |_, j| j == i }.map(&:first)
          [i, others.sum { |o| Speaker::VectorMath.cosine_similarity(emb, o) } / others.size.to_f]
        end
        min_idx, min_sim = avg_sims.min_by { |_, sim| sim }
        min_sim < OUTLIER_THRESHOLD ? [min_idx, min_sim] : [nil, nil]
      end

      def self.confirm_exclusion?(clip, similarity)
        text_preview = clip[:segment].text[0, 40]
        print "  Clip \"#{text_preview}\" has low similarity (#{similarity.round(2)}). Exclude? [Y/n]: "
        answer = $stdin.gets
        answer.nil? || answer.strip.empty? || answer.strip.casecmp("y").zero?
      end

      private_class_method :scan_recordings, :build_recording_entry,
                           :process_recording, :collect_updates, :print_recording_header,
                           :learn_speaker, :play_clips, :encode_clips,
                           :filter_outliers, :warn_low_pair_similarity, :exclude_outlier,
                           :find_outlier, :confirm_exclusion?
    end
  end
end
