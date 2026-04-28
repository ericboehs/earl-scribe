# frozen_string_literal: true

require "json"
require "test_helper"
require "tmpdir"
require "earl_scribe/cli/whisperkit_diarize"

module EarlScribe
  module Cli
    class WhisperkitDiarizeTest < Minitest::Test
      def setup
        @dir = Dir.mktmpdir
        @paths = {
          transcript: File.join(@dir, "x.txt"),
          jsonl: File.join(@dir, "x.jsonl"),
          wav: File.join(@dir, "x.wav")
        }
      end

      def teardown
        FileUtils.rm_rf(@dir)
      end

      test "skips when wav missing" do
        File.write(@paths[:jsonl], "{}\n")
        WhisperkitDiarize.run(@paths)
        assert_not File.exist?(@paths[:transcript])
      end

      test "skips when jsonl missing" do
        File.write(@paths[:wav], "fake")
        WhisperkitDiarize.run(@paths)
        assert_not File.exist?(@paths[:transcript])
      end

      test "parse_rttm extracts start/end/speaker from token positions" do
        path = File.join(@dir, "out.rttm")
        File.write(path, <<~RTTM)
          SPEAKER out 1 0.000 2.869 <NA> <NA> A <NA> <NA>
          SPEAKER out 1 6.825 2.309 <NA> <NA> B <NA> <NA>
          # comment ignored
        RTTM
        segments = WhisperkitDiarize.parse_rttm(path)
        assert_equal 2, segments.size
        assert_in_delta 0.000, segments[0][:start], 1e-6
        assert_in_delta 2.869, segments[0][:end], 1e-6
        assert_equal "Speaker A", segments[0][:speaker]
        assert_equal "Speaker B", segments[1][:speaker]
      end

      test "parse_rttm tolerates text in ortho slot" do
        path = File.join(@dir, "out.rttm")
        File.write(path, "SPEAKER out 1 0.020 8.860 like kind of between a rock <NA> A <NA> <NA>\n")
        assert_equal "Speaker A", WhisperkitDiarize.parse_rttm(path).first[:speaker]
      end

      test "speaker_at picks segment with greatest overlap" do
        diar = [{ start: 0, end: 5, speaker: "Speaker A" },
                { start: 5, end: 10, speaker: "Speaker B" }]
        seg = { "start_time" => 4, "end_time" => 8 }  # 1s in A, 3s in B
        assert_equal "Speaker B", WhisperkitDiarize.speaker_at(seg, diar)
      end

      test "speaker_at falls back to nearest when seg in a gap" do
        diar = [{ start: 0, end: 2, speaker: "Speaker A" },
                { start: 5, end: 10, speaker: "Speaker B" }]
        seg = { "start_time" => 3, "end_time" => 4 }  # in gap, closer to A (1s) than B (1s)
        result = WhisperkitDiarize.speaker_at(seg, diar)
        assert_includes ["Speaker A", "Speaker B"], result
      end

      test "speaker_at preserves existing speaker when no diar segments" do
        seg = { "start_time" => 0, "end_time" => 5, "speaker" => "Speaker 0" }
        assert_equal "Speaker 0", WhisperkitDiarize.speaker_at(seg, [])
      end

      test "splice_jsonl rewrites speaker labels and regenerates txt" do
        File.write(@paths[:jsonl], <<~JSONL)
          {"speaker":"Speaker 0","text":"hello","start_time":0.0,"end_time":2.0,"channel":0}
          {"speaker":"Speaker 0","text":"world","start_time":2.5,"end_time":4.0,"channel":0}
        JSONL
        diar = [{ start: 0, end: 2.5, speaker: "Speaker A" },
                { start: 2.5, end: 5, speaker: "Speaker B" }]
        WhisperkitDiarize.splice_jsonl(@paths[:jsonl], diar)
        WhisperkitDiarize.regenerate_txt(@paths[:jsonl], @paths[:transcript])
        lines = File.readlines(@paths[:jsonl]).map { |l| JSON.parse(l) }
        assert_equal "Speaker A", lines[0]["speaker"]
        assert_equal "Speaker B", lines[1]["speaker"]
        txt = File.read(@paths[:transcript])
        assert_includes txt, "Speaker A: hello"
        assert_includes txt, "Speaker B: world"
      end

      test "run shells out to whisperkit-cli diarize and splices output" do
        File.write(@paths[:wav], "fake")
        File.write(@paths[:jsonl],
                   "{\"speaker\":\"Speaker 0\",\"text\":\"hi\",\"start_time\":0.0,\"end_time\":1.0,\"channel\":0}\n")
        rttm_content = "SPEAKER x 1 0.0 1.5 <NA> <NA> A <NA> <NA>\n"
        Open3.stub(:capture3, lambda { |*args|
          rttm_path = args[args.index("--rttm-path") + 1]
          File.write(rttm_path, rttm_content)
          ["", "", fake_status(success: true)]
        }) do
          WhisperkitDiarize.run(@paths, consolidate: false)
        end
        assert_includes File.read(@paths[:transcript]), "Speaker A: hi"
      end

      test "run logs error and bails when diarize fails" do
        File.write(@paths[:wav], "fake")
        File.write(@paths[:jsonl],
                   "{\"speaker\":\"Speaker 0\",\"text\":\"hi\",\"start_time\":0.0,\"end_time\":1.0,\"channel\":0}\n")
        original_jsonl = File.read(@paths[:jsonl])
        Open3.stub(:capture3, ->(*_) { ["", "boom", fake_status(success: false)] }) do
          WhisperkitDiarize.run(@paths)
        end
        assert_equal original_jsonl, File.read(@paths[:jsonl])
      end

      test "audio_source falls back to recording when wav missing" do
        File.write(@paths[:wav].sub(".wav", ".m4a"), "fake-m4a")
        paths = @paths.merge(recording: @paths[:wav].sub(".wav", ".m4a"))
        assert_equal paths[:recording], WhisperkitDiarize.audio_source(paths)
      end

      test "audio_source returns nil when neither wav nor recording exists" do
        assert_nil WhisperkitDiarize.audio_source(@paths)
      end

      test "audio_source prefers wav when both exist" do
        File.write(@paths[:wav], "wav")
        File.write(@paths[:wav].sub(".wav", ".m4a"), "m4a")
        paths = @paths.merge(recording: @paths[:wav].sub(".wav", ".m4a"))
        assert_equal @paths[:wav], WhisperkitDiarize.audio_source(paths)
      end

      test "consolidate is opt-out via consolidate: false" do
        segments = [{ start: 0, end: 5, speaker: "Speaker A" }]
        result = WhisperkitDiarize.consolidate(segments, "/tmp/x.m4a", consolidate: false)
        assert_equal segments, result
      end

      test "consolidate returns segments unchanged when remap_labels yields nothing" do
        segments = [{ start: 0, end: 5, speaker: "Speaker A" }]
        WhisperkitConsolidate.stub(:remap_labels, {}) do
          assert_equal segments, WhisperkitDiarize.consolidate(segments, "/tmp/x.m4a", {})
        end
      end

      test "consolidate applies remap_labels to relabel speakers" do
        segments = [{ start: 0, end: 5, speaker: "Speaker A" },
                    { start: 5, end: 10, speaker: "Speaker B" }]
        WhisperkitConsolidate.stub(:remap_labels, { "Speaker A" => "Allison" }) do
          result = WhisperkitDiarize.consolidate(segments, "/tmp/x.m4a", {})
          assert_equal "Allison", result[0][:speaker]
          assert_equal "Speaker B", result[1][:speaker] # unmapped stays
        end
      end

      test "segment? rejects metadata lines" do
        assert_not WhisperkitDiarize.segment?({ "type" => "metadata" })
      end

      test "segment? rejects lines without start/end times" do
        assert_not WhisperkitDiarize.segment?({ "speaker" => "x" })
      end

      test "segment? accepts segment lines" do
        assert WhisperkitDiarize.segment?({ "start_time" => 0, "end_time" => 1, "speaker" => "x" })
      end

      test "safe_parse returns nil on malformed JSON" do
        assert_nil WhisperkitDiarize.safe_parse("not json")
      end

      test "safe_parse parses valid JSON" do
        assert_equal({ "a" => 1 }, WhisperkitDiarize.safe_parse('{"a":1}'))
      end

      test "speaker_at returns existing speaker when no diar segments overlap and list is empty" do
        seg = { "start_time" => 0, "end_time" => 5, "speaker" => "kept" }
        assert_equal "kept", WhisperkitDiarize.speaker_at(seg, [])
      end

      test "run_diarize passes --num-speakers when provided" do
        path = File.join(@dir, "x.rttm")
        captured = []
        Open3.stub(:capture3, lambda { |*args|
          captured << args
          File.write(args[args.index("--rttm-path") + 1], "SPEAKER x 1 0.0 1.0 <NA> <NA> A <NA> <NA>\n")
          ["", "", fake_status(success: true)]
        }) do
          WhisperkitDiarize.run_diarize(@paths[:wav], num_speakers: 3)
          FileUtils.rm_f(path)
        end
        assert_includes captured.first, "--num-speakers"
        assert_includes captured.first, "3"
      end

      test "splice_jsonl preserves non-segment lines" do
        File.write(@paths[:jsonl], <<~JSONL)
          {"type":"metadata","note":"hi"}
          {"speaker":"Speaker 0","text":"hello","start_time":0.0,"end_time":2.0}
        JSONL
        WhisperkitDiarize.splice_jsonl(@paths[:jsonl], [{ start: 0, end: 5, speaker: "Speaker A" }])
        lines = File.readlines(@paths[:jsonl]).map { |l| JSON.parse(l) }
        assert_equal "metadata", lines[0]["type"]
        # metadata keeps no speaker field added since segment? returns false
        refute_equal "Speaker A", lines[0]["speaker"]
        assert_equal "Speaker A", lines[1]["speaker"]
      end

      test "regenerate_txt skips metadata lines" do
        File.write(@paths[:jsonl], <<~JSONL)
          {"type":"metadata","note":"hi"}
          {"speaker":"X","text":"hello","start_time":0.0,"end_time":2.0}
          not json
        JSONL
        WhisperkitDiarize.regenerate_txt(@paths[:jsonl], @paths[:transcript])
        txt = File.read(@paths[:transcript])
        assert_includes txt, "X: hello"
        refute_match(/metadata/, txt)
      end

      test "overlap_or_distance distinguishes overlap from gap before vs after" do
        diar = { start: 5, end: 10 }
        assert_in_delta(-3.0, WhisperkitDiarize.overlap_or_distance(diar, 0, 2), 1e-6) # before
        assert_in_delta(-2.0, WhisperkitDiarize.overlap_or_distance(diar, 12, 15), 1e-6) # after
        assert_in_delta(2.0, WhisperkitDiarize.overlap_or_distance(diar, 4, 7), 1e-6)    # overlap
      end

      private

      def fake_status(success:)
        status = Object.new
        status.define_singleton_method(:success?) { success }
        status.define_singleton_method(:exitstatus) { success ? 0 : 1 }
        status
      end
    end
  end
end
