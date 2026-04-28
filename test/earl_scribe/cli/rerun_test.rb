# frozen_string_literal: true

require "stringio"
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
        write_fake_wav(@paths[:wav])
        eou = '{"type":"eou","text":"hello","start_sec":0,"audio_sec":1,"speaker":0}'
        out = "{\"type\":\"start\",\"audio_duration_sec\":2}\n#{eou}\n"
        with_popen3_stub(out: out, success: true) do
          Open3.stub(:capture3, ->(*_) { ["", "", fake_status(success: true)] }) do
            capture_io { Rerun.run(@paths, {}) }
          end
        end
        assert File.exist?(@paths[:transcript_live])
        assert_includes File.read(@paths[:transcript]), "Speaker 0: hello"
        assert_not File.exist?(@paths[:wav])
      end

      test "restores live when file pass fails" do
        File.write(@paths[:transcript], "live txt")
        File.write(@paths[:jsonl], "{}\n")
        write_fake_wav(@paths[:wav])
        with_popen3_stub(out: "", err: "boom", success: false) do
          Open3.stub(:capture3, ->(*_) { ["", "", fake_status(success: false)] }) do
            capture_io { Rerun.run(@paths, {}) }
          end
        end
        assert_equal "live txt", File.read(@paths[:transcript])
        assert_not File.exist?(@paths[:transcript_live])
      end

      test "Interrupt during rerun keeps live as final" do
        File.write(@paths[:transcript], "live txt")
        write_fake_wav(@paths[:wav])
        Open3.stub(:popen3, ->(*_) { raise Interrupt }) do
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

      test "file_pass_command uses streaming chunk-ms when rerun_model is streaming" do
        Config.stub(:rerun_model, "streaming") do
          Config.stub(:rerun_chunk_ms, 320) do
            cmd = Rerun.file_pass_command("/tmp/x.wav", {})
            assert_includes cmd, "320"
            assert_not_includes cmd, "--batch"
          end
        end
      end

      test "file_pass_command uses --batch when rerun_model is batch" do
        Config.stub(:rerun_model, "batch") do
          cmd = Rerun.file_pass_command("/tmp/x.wav", {})
          assert_includes cmd, "--batch"
          assert_not_includes cmd, "--chunk-ms"
        end
      end

      test "wav_duration_sec parses RIFF header data size" do
        write_fake_wav(@paths[:wav], data_bytes: 16_000 * 2 * 2) # 2 seconds @ Int16
        assert_in_delta 2.0, RerunAudio.wav_duration_sec(@paths[:wav]), 1e-6
      end

      test "report_timing prints elapsed and rate when wav has duration" do
        write_fake_wav(@paths[:wav], data_bytes: 16_000 * 2 * 60) # 60s @ Int16
        _stdout, stderr = capture_io { Rerun.report_timing(Time.now - 5, @paths[:wav]) }
        assert_match(/rerun done in \d+\.\d+s/, stderr)
        assert_match(/real-time/, stderr)
      end

      test "report_timing omits real-time rate when duration unavailable" do
        # Empty file → wav_duration_sec returns nil
        empty = File.join(@dir, "empty.wav")
        File.write(empty, "")
        _stdout, stderr = capture_io { Rerun.report_timing(Time.now - 5, empty) }
        assert_match(/rerun done in/, stderr)
        refute_match(/real-time/, stderr)
      end

      test "Interrupt with no live transcript leaves files untouched" do
        write_fake_wav(@paths[:wav])
        Open3.stub(:popen3, ->(*_) { raise Interrupt }) do
          capture_io { Rerun.run(@paths, {}) }
        end
        assert_not File.exist?(@paths[:transcript])
      end

      test "relocate_live is a no-op when transcripts do not exist" do
        # Files don't exist; should not raise
        Rerun.relocate_live(@paths)
        assert_not File.exist?(@paths[:transcript_live])
      end

      test "restore_live is a no-op when live files do not exist" do
        Rerun.restore_live(@paths)
        assert_not File.exist?(@paths[:transcript])
      end

      test "finalize skips m4a encode when recording path is nil" do
        File.write(@paths[:wav], "fake")
        paths = @paths.merge(recording: nil)
        # Should not raise — encode_m4a not called
        Rerun.finalize(paths)
        assert_not File.exist?(@paths[:wav])
      end

      test "rerun_ready? rejects nil wav" do
        assert_not Rerun.rerun_ready?(nil)
      end

      test "consume_pass starts and kills spinner in batch mode" do
        spinner_killed = false
        spinner = Object.new
        spinner.define_singleton_method(:kill) { spinner_killed = true }
        Config.stub(:rerun_model, "batch") do
          RerunProgress.stub(:start_spinner, spinner) do
            RerunEvents.stub(:stream_to_files, ->(*) {}) do
              RerunProgress.stub(:clear, ->(*) {}) do
                Rerun.consume_pass(StringIO.new(""), @paths, time_offset_sec: 0.0)
              end
            end
          end
        end
        assert spinner_killed
      end

      test "rerun_ready? rejects missing wav" do
        assert_not Rerun.rerun_ready?("/nonexistent.wav")
      end

      test "execute_pass uses unnormalized wav when normalize fails" do
        File.write(@paths[:transcript], "live")
        File.write(@paths[:jsonl], "{}\n")
        write_fake_wav(@paths[:wav])
        eou = '{"type":"eou","text":"x","start_sec":0,"audio_sec":1,"speaker":0}'
        out = "{\"type\":\"start\",\"audio_duration_sec\":2}\n#{eou}\n"
        # Stub normalize_wav to return nil (failed/no-op) — pad should be 0.0
        RerunAudio.stub(:normalize_wav, nil) do
          RerunAudio.stub(:encode_m4a, nil) do
            with_popen3_stub(out: out, success: true) do
              capture_io { Rerun.run(@paths, {}) }
            end
          end
        end
        assert File.exist?(@paths[:transcript_live])
      end

      private

      def fake_status(success:)
        status = Object.new
        status.define_singleton_method(:success?) { success }
        status.define_singleton_method(:exitstatus) { success ? 0 : 1 }
        status
      end

      def write_fake_wav(path, data_bytes: 1_000)
        header = "RIFF".dup
        header << [36 + data_bytes].pack("V")
        header << "WAVEfmt "
        header << [16].pack("V") << [3].pack("v") << [1].pack("v")
        header << [16_000].pack("V") << [64_000].pack("V") << [4].pack("v") << [32].pack("v")
        header << "data"
        header << [data_bytes].pack("V")
        File.binwrite(path, header + ("\x00" * data_bytes))
      end

      def with_popen3_stub(out:, err: "", success: true, &block)
        status = fake_status(success: success)
        wait_thr = Object.new
        wait_thr.define_singleton_method(:value) { status }
        Open3.stub(:popen3, lambda { |*_args|
          [StringIO.new, StringIO.new(out), StringIO.new(err), wait_thr]
        }, &block)
      end
    end
  end
end
