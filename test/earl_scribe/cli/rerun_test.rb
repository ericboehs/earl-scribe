# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Cli
    class RerunTest < Minitest::Test
      def setup
        @dir = Dir.mktmpdir
        @paths = {
          transcript: File.join(@dir, "x.txt"),
          jsonl: File.join(@dir, "x.jsonl"),
          transcript_live: File.join(@dir, "x-live.txt"),
          jsonl_live: File.join(@dir, "x-live.jsonl"),
          wav: File.join(@dir, "x.wav"),
          recording: File.join(@dir, "x.m4a")
        }
      end

      def teardown
        FileUtils.rm_rf(@dir)
      end

      test "skips when wav missing" do
        capture_io { Rerun.run(@paths, {}) }
        assert_not File.exist?(@paths[:transcript_live])
      end

      test "skips when wav is just header" do
        File.write(@paths[:wav], "RIFF#{"\x00" * 36}")
        capture_io { Rerun.run(@paths, {}) }
        assert_not File.exist?(@paths[:transcript_live])
      end

      test "renames live, runs file pass, writes new transcripts, drops wav" do
        File.write(@paths[:transcript], "live txt")
        File.write(@paths[:jsonl], "{}\n")
        File.write(@paths[:wav], "0" * 200)
        eou = '{"type":"eou","text":"hello","start_sec":0,"audio_sec":1,"speaker":0}'
        out = "{\"type\":\"start\"}\n#{eou}\n"
        Open3.stub(:capture3, lambda { |*args|
          if args.first.include?("ffmpeg")
            ["", "", fake_status(success: true)]
          else
            [out, "", fake_status(success: true)]
          end
        }) do
          capture_io { Rerun.run(@paths, {}) }
        end
        assert File.exist?(@paths[:transcript_live])
        assert_includes File.read(@paths[:transcript]), "Speaker 0: hello"
        assert_not File.exist?(@paths[:wav])
      end

      test "restores live when file pass fails" do
        File.write(@paths[:transcript], "live txt")
        File.write(@paths[:jsonl], "{}\n")
        File.write(@paths[:wav], "0" * 200)
        Open3.stub(:capture3, ->(*_) { ["", "boom", fake_status(success: false)] }) do
          capture_io { Rerun.run(@paths, {}) }
        end
        assert_equal "live txt", File.read(@paths[:transcript])
        assert_not File.exist?(@paths[:transcript_live])
      end

      test "Interrupt during rerun keeps live as final" do
        File.write(@paths[:transcript], "live txt")
        File.write(@paths[:wav], "0" * 200)
        Open3.stub(:capture3, ->(*_) { raise Interrupt }) do
          capture_io { Rerun.run(@paths, {}) }
        end
        assert File.exist?(@paths[:transcript])
        assert_equal "live txt", File.read(@paths[:transcript])
      end

      test "file_pass_command appends diar variant and wait when set" do
        cmd = Rerun.file_pass_command("/tmp/x.wav", diar_variant: "fastV2", diar_wait_ms: 6000)
        assert_includes cmd, "fastV2"
        assert_includes cmd, "6000"
        assert_includes cmd, "--file"
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
