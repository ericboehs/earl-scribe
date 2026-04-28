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
          WhisperkitDiarize.run(@paths)
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
