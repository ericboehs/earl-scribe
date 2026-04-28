# frozen_string_literal: true

require_relative "learn_rewriter"

module EarlScribe
  module Cli
    # Speaker resolution + segment-write helpers split out of Cli::Transcribe to
    # keep that orchestration module under the lint length budget.
    module TranscribeSpeakerWriter
      module_function

      SPEAKER_RE = /\A((?:Ch\d+ )?)Speaker (\d+)\z/.freeze
      CACHE_KEY_RE = /\A((?:Ch\d+ )?)(\d+)\z/.freeze

      def handle_result(result, resolver, ctx, per_segment: false)
        prefix = ctx.capture.channels > 1 ? "Ch#{result[:channel_index]}" : nil
        Transcription::WordGrouper.group(result[:words], speaker_prefix: prefix).each do |seg|
          seg.channel = result[:channel_index]
          cache_key = resolve_speaker(seg, result[:words], resolver, per_segment: per_segment)
          write_segment(ctx, seg, cache_key)
        end
      end

      def write_segment(ctx, seg, cache_key)
        seg.cache_key = cache_key
        ctx.term_display.commit(seg, cache_key: cache_key)
        ctx.writer.write_line(seg.to_timestamped_s)
        ctx.jsonl.write_segment(seg)
      end

      # When `per_segment` is true (WhisperKit engine — every chunk arrives
      # labeled "Speaker 0"), mint a unique cache_key per segment so each one
      # gets identified independently rather than collapsing into a single
      # cached label.
      def resolve_speaker(seg, words, resolver, per_segment: false)
        return unless resolver

        cache_key = build_cache_key(seg, per_segment: per_segment)
        return unless cache_key

        if (name = resolver.resolve_label(cache_key, words, channel: seg.channel))
          seg.original_speaker = seg.speaker
          seg.speaker = name
        end
        cache_key
      end

      def build_cache_key(seg, per_segment:)
        return "wk-#{seg.start_time}-#{seg.end_time}" if per_segment

        match = seg.speaker&.match(SPEAKER_RE)
        match ? "#{match[1]}#{match[2]}" : nil
      end

      def correct_files(ctx, map)
        return unless map&.any?

        LearnRewriter.rewrite({ jsonl_path: ctx.paths[:jsonl] },
                              map.transform_keys { |k| cache_key_to_speaker_label(k) })
      end

      def cache_key_to_speaker_label(key)
        return "Speaker 0" if key.start_with?("wk-")

        (m = key.match(CACHE_KEY_RE)) ? "#{m[1]}Speaker #{m[2]}" : key
      end
    end
  end
end
