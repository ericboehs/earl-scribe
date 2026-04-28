# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

require_relative "whisperkit_consolidate"

module EarlScribe
  module Cli
    # Post-session diarization pass for the WhisperKit engine. Runs
    # `whisperkit-cli diarize` on the captured WAV, parses the resulting RTTM,
    # and splices speaker labels into the JSONL transcript that LocalStream
    # wrote with placeholder Speaker 0 for every segment. The text transcript
    # is regenerated from the updated JSONL.
    module WhisperkitDiarize
      module_function

      DIARIZE_BIN = "whisperkit-cli"

      def run(paths, opts = {})
        audio = audio_source(paths)
        return unless audio && File.exist?(paths[:jsonl])

        warn "\nRunning diarization on captured audio..."
        rttm = run_diarize(audio, num_speakers: opts[:diar_num_speakers])
        segments = rttm ? parse_rttm(rttm) : []
        apply_segments(paths, audio, segments, opts) unless segments.empty?
        FileUtils.rm_f(rttm) if rttm && !ENV["EARL_SCRIBE_KEEP_RTTM"]
      end

      def apply_segments(paths, audio, segments, opts)
        consolidated = consolidate(segments, audio, opts)
        splice_jsonl(paths[:jsonl], consolidated)
        regenerate_txt(paths[:jsonl], paths[:transcript])
      end

      def consolidate(segments, audio, opts)
        return segments if opts[:consolidate] == false

        remap = WhisperkitConsolidate.remap_labels(segments, audio)
        return segments if remap.empty?

        warn "Consolidating #{remap.size} cluster(s): #{remap.map { |k, v| "#{k} -> #{v}" }.join(", ")}"
        segments.map { |seg| seg.merge(speaker: remap[seg[:speaker]] || seg[:speaker]) }
      end

      def audio_source(paths)
        wav = paths[:wav]
        return wav if wav && File.exist?(wav)

        recording = paths[:recording]
        recording if recording && File.exist?(recording)
      end

      def run_diarize(wav, num_speakers: nil)
        rttm = "#{wav}.rttm"
        cmd = [DIARIZE_BIN, "diarize", "--audio-path", wav, "--rttm-path", rttm]
        cmd += ["--num-speakers", num_speakers.to_s] if num_speakers
        _out, err, status = Open3.capture3(*cmd)
        return rttm if status.success? && File.exist?(rttm)

        EarlScribe.logger.error("whisperkit-cli diarize failed: #{err.lines.last(2).join.strip}")
        nil
      end

      # whisperkit-cli emits RTTM with the transcribed text in the ortho slot,
      # so a regex on field positions is fragile. Tokenize and pull what we
      # need by position from the start (start/dur) and the end (speaker
      # label is third-from-last in the standard 10-field layout).
      def parse_rttm(path)
        File.readlines(path).filter_map do |line|
          tokens = line.strip.split(/\s+/)
          next unless tokens.first == "SPEAKER" && tokens.length >= 10

          start_sec = tokens[3].to_f
          { start: start_sec, end: start_sec + tokens[4].to_f, speaker: "Speaker #{tokens[-3]}" }
        end
      end

      def splice_jsonl(path, diar_segments)
        lines = File.readlines(path).filter_map { |l| safe_parse(l) }
        updated = lines.map { |seg| segment?(seg) ? seg.merge("speaker" => speaker_at(seg, diar_segments)) : seg }
        File.open(path, "w") { |f| updated.each { |seg| f.puts(JSON.generate(seg)) } }
      end

      def segment?(seg)
        seg["type"] != "metadata" && seg.key?("start_time") && seg.key?("end_time")
      end

      def safe_parse(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      # whisperkit-cli's RTTM omits silent intervals, so a transcript segment's
      # midpoint can fall in a diar gap. Pick the diar segment with the most
      # temporal overlap; if none overlaps, fall back to the nearest one by
      # boundary distance.
      def speaker_at(seg, diar_segments)
        seg_start = seg["start_time"].to_f
        seg_end = seg["end_time"].to_f
        scored = diar_segments.map { |d| [overlap_or_distance(d, seg_start, seg_end), d] }
        best = scored.max_by(&:first)
        best && best[1] ? best[1][:speaker] : seg["speaker"]
      end

      def overlap_or_distance(diar, seg_start, seg_end)
        overlap = [diar[:end], seg_end].min - [diar[:start], seg_start].max
        return overlap if overlap.positive?

        distance = if seg_end <= diar[:start]
                     diar[:start] - seg_end
                   else
                     seg_start - diar[:end]
                   end
        -distance
      end

      def regenerate_txt(jsonl_path, txt_path)
        File.open(txt_path, "w") do |out|
          File.foreach(jsonl_path) do |line|
            seg = safe_parse(line)
            out.puts(format_segment(seg)) if seg && segment?(seg)
          end
        end
      end

      def format_segment(seg)
        secs = seg["start_time"].to_i
        ts = format("%<h>02d:%<m>02d:%<s>02d", h: secs / 3600, m: (secs % 3600) / 60, s: secs % 60)
        "[#{ts}] #{seg["speaker"]}: #{seg["text"]}"
      end
    end
  end
end
