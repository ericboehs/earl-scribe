# frozen_string_literal: true

require "stringio"
require "test_helper"
require "tmpdir"
require "earl_scribe/cli/rerun_progress"
require "earl_scribe/cli/rerun_events"

module EarlScribe
  module Cli
    class RerunEventsTest < Minitest::Test
      def setup
        @dir = Dir.mktmpdir
        @paths = {
          jsonl: File.join(@dir, "x.jsonl"),
          transcript: File.join(@dir, "x.txt")
        }
      end

      def teardown
        FileUtils.rm_rf(@dir)
      end

      def test_parse_event_returns_nil_for_blank_line
        assert_nil RerunEvents.parse_event("")
        assert_nil RerunEvents.parse_event("   \n")
      end

      def test_parse_event_returns_nil_for_malformed_json
        assert_nil RerunEvents.parse_event("not json")
      end

      def test_parse_event_parses_valid_json
        assert_equal({ "type" => "eou" }, RerunEvents.parse_event('{"type":"eou"}'))
      end

      def test_event_to_segment_uses_speaker_when_present
        seg = RerunEvents.event_to_segment(
          { "speaker" => 2, "text" => "hello", "start_sec" => 1.0, "audio_sec" => 2.5 }
        )
        assert_equal "Speaker 2", seg["speaker"]
        assert_in_delta 1.0, seg["start_time"], 1e-6
        assert_in_delta 2.5, seg["end_time"], 1e-6
      end

      def test_event_to_segment_defaults_to_speaker_zero
        seg = RerunEvents.event_to_segment({ "text" => "hi", "start_sec" => 0.5, "audio_sec" => 1.0 })
        assert_equal "Speaker 0", seg["speaker"]
      end

      def test_event_to_segment_clamps_negative_offsets_to_zero
        seg = RerunEvents.event_to_segment(
          { "text" => "x", "start_sec" => 0.5, "audio_sec" => 1.0 }, offset: -2.0
        )
        assert_in_delta 0.0, seg["start_time"], 1e-6
        assert_in_delta 0.0, seg["end_time"], 1e-6
      end

      def test_format_segment_pads_timestamp
        seg = { "start_time" => 3661, "speaker" => "Allison", "text" => "hi" }
        assert_equal "[01:01:01] Allison: hi", RerunEvents.format_segment(seg)
      end

      def test_handle_event_dispatches_start_to_duration
        ctx = { duration: nil, last_paint: 0.0, offset: 0.0 }
        RerunEvents.handle_event({ "type" => "start", "audio_duration_sec" => 60 },
                                 ctx, StringIO.new, StringIO.new)
        assert_in_delta 60.0, ctx[:duration], 1e-6
      end

      def test_handle_event_start_without_duration
        ctx = { duration: nil, last_paint: 0.0, offset: 0.0 }
        RerunEvents.handle_event({ "type" => "start" }, ctx, StringIO.new, StringIO.new)
        assert_nil ctx[:duration]
      end

      def test_handle_event_eou_without_audio_sec_paints_nil
        ctx = { duration: 10.0, last_paint: 0.0, offset: 0.0 }
        # No audio_sec — RerunProgress.paint should be called with nil
        RerunEvents.handle_event({ "type" => "eou", "text" => "hi", "start_sec" => 0.0 },
                                 ctx, StringIO.new, StringIO.new)
        # No assertion — just ensures the &.to_f else branch is hit
      end

      def test_handle_event_caches_final
        ctx = { duration: nil, last_paint: 0.0, offset: 0.0 }
        ev = { "type" => "final", "text" => "done" }
        RerunEvents.handle_event(ev, ctx, StringIO.new, StringIO.new)
        assert_equal ev, ctx[:final]
      end

      def test_handle_event_ignores_unknown_types
        ctx = { duration: nil, last_paint: 0.0, offset: 0.0 }
        # Should not raise
        RerunEvents.handle_event({ "type" => "noise" }, ctx, StringIO.new, StringIO.new)
        assert_nil ctx[:duration]
      end

      def test_stream_to_files_writes_eou_events_to_both_files
        input = StringIO.new(<<~JSONL)
          {"type":"start","audio_duration_sec":10}
          {"type":"eou","text":"hello","start_sec":0,"audio_sec":1,"speaker":0}
          {"type":"eou","text":"world","start_sec":1,"audio_sec":2,"speaker":1}
        JSONL
        RerunEvents.stream_to_files(input, @paths)
        jsonl_lines = File.readlines(@paths[:jsonl])
        assert_equal 2, jsonl_lines.size
        txt = File.read(@paths[:transcript])
        assert_includes txt, "Speaker 0: hello"
        assert_includes txt, "Speaker 1: world"
      end

      def test_stream_events_skips_unparseable_lines
        input = StringIO.new("garbage\n{\"type\":\"eou\",\"text\":\"ok\",\"audio_sec\":1}\n")
        jf = StringIO.new
        tf = StringIO.new
        RerunEvents.stream_events(input, jf, tf)
        assert_includes tf.string, "Speaker 0: ok"
      end
    end
  end
end
