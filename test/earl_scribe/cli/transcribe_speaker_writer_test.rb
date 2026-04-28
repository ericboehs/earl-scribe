# frozen_string_literal: true

require "test_helper"
require "earl_scribe/cli/transcribe_speaker_writer"

module EarlScribe
  module Cli
    class TranscribeSpeakerWriterTest < Minitest::Test
      Seg = Struct.new(:speaker, :original_speaker, :start_time, :end_time, :channel, :cache_key,
                       keyword_init: true) do
        def to_timestamped_s
          "[00:00] #{speaker}: text"
        end
      end

      def test_resolve_speaker_returns_nil_without_resolver
        seg = Seg.new(speaker: "Speaker 0")
        assert_nil TranscribeSpeakerWriter.resolve_speaker(seg, [], nil)
      end

      def test_resolve_speaker_returns_nil_when_speaker_label_does_not_match
        resolver = Object.new
        resolver.define_singleton_method(:resolve_label) { |*| raise "should not be called" }
        seg = Seg.new(speaker: "Allison") # already a real name; SPEAKER_RE won't match
        assert_nil TranscribeSpeakerWriter.resolve_speaker(seg, [], resolver)
      end

      def test_resolve_speaker_uses_cache_key_from_speaker_label
        resolver = build_resolver_returning(nil)
        seg = Seg.new(speaker: "Speaker 3")
        assert_equal "3", TranscribeSpeakerWriter.resolve_speaker(seg, [], resolver)
      end

      def test_resolve_speaker_relabels_when_resolver_returns_name
        resolver = build_resolver_returning("Allison")
        seg = Seg.new(speaker: "Speaker 0")
        TranscribeSpeakerWriter.resolve_speaker(seg, [], resolver)
        assert_equal "Allison", seg.speaker
        assert_equal "Speaker 0", seg.original_speaker
      end

      def test_resolve_speaker_per_segment_uses_unique_cache_key
        captured = []
        resolver = Object.new
        resolver.define_singleton_method(:resolve_label) do |key, *|
          captured << key
          nil
        end
        a = Seg.new(speaker: "Speaker 0", start_time: 0.0, end_time: 1.0)
        b = Seg.new(speaker: "Speaker 0", start_time: 2.0, end_time: 3.0)
        TranscribeSpeakerWriter.resolve_speaker(a, [], resolver, per_segment: true)
        TranscribeSpeakerWriter.resolve_speaker(b, [], resolver, per_segment: true)
        assert_equal 2, captured.uniq.size
        assert(captured.all? { |k| k.start_with?("wk-") })
      end

      def test_cache_key_to_speaker_label_handles_per_segment_keys
        assert_equal "Speaker 0", TranscribeSpeakerWriter.cache_key_to_speaker_label("wk-0.0-1.5")
      end

      def test_cache_key_to_speaker_label_handles_channel_prefixed_keys
        assert_equal "Ch1 Speaker 2", TranscribeSpeakerWriter.cache_key_to_speaker_label("Ch1 2")
      end

      def test_cache_key_to_speaker_label_returns_unparseable_keys_unchanged
        assert_equal "weird", TranscribeSpeakerWriter.cache_key_to_speaker_label("weird")
      end

      def test_correct_files_no_op_on_empty_map
        ctx = Struct.new(:paths).new({ jsonl: "/dev/null" })
        # Should not call LearnRewriter (which would explode on /dev/null)
        TranscribeSpeakerWriter.correct_files(ctx, {})
        TranscribeSpeakerWriter.correct_files(ctx, nil)
      end

      private

      def build_resolver_returning(name)
        resolver = Object.new
        resolver.define_singleton_method(:resolve_label) { |*| name }
        resolver
      end
    end
  end
end
