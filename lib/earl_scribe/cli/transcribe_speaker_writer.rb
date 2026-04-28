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

      def handle_result(result, resolver, ctx)
        prefix = ctx.capture.channels > 1 ? "Ch#{result[:channel_index]}" : nil
        Transcription::WordGrouper.group(result[:words], speaker_prefix: prefix).each do |seg|
          seg.channel = result[:channel_index]
          write_segment(ctx, seg, resolve_speaker(seg, result[:words], resolver))
        end
      end

      def write_segment(ctx, seg, cache_key)
        seg.cache_key = cache_key
        ctx.term_display.commit(seg, cache_key: cache_key)
        ctx.writer.write_line(seg.to_timestamped_s)
        ctx.jsonl.write_segment(seg)
      end

      def resolve_speaker(seg, words, resolver)
        return unless (match = resolver && seg.speaker&.match(SPEAKER_RE))

        cache_key = "#{match[1]}#{match[2]}"
        if (name = resolver.resolve_label(cache_key, words, channel: seg.channel))
          seg.original_speaker = seg.speaker
          seg.speaker = name
        end
        cache_key
      end

      def correct_files(ctx, map)
        return unless map&.any?

        LearnRewriter.rewrite({ jsonl_path: ctx.paths[:jsonl] },
                              map.transform_keys { |k| cache_key_to_speaker_label(k) })
      end

      def cache_key_to_speaker_label(key)
        (m = key.match(CACHE_KEY_RE)) ? "#{m[1]}Speaker #{m[2]}" : key
      end
    end
  end
end
