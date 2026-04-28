# frozen_string_literal: true

require "json"

module EarlScribe
  module Cli
    # Streams JSONL events from the rerun ASR pass to transcript+jsonl files
    # while painting the progress bar. Lifted out of Cli::Rerun.
    module RerunEvents
      module_function

      def stream_to_files(stdout, paths, offset: 0.0)
        File.open(paths[:jsonl], "w") do |jf|
          File.open(paths[:transcript], "w") do |tf|
            stream_events(stdout, jf, tf, offset: offset)
          end
        end
      end

      def stream_events(stdout, jsonl_file, txt_file, offset: 0.0)
        ctx = { duration: nil, last_paint: 0.0, offset: offset }
        stdout.each_line do |line|
          event = parse_event(line)
          handle_event(event, ctx, jsonl_file, txt_file) if event
        end
        RerunProgress.clear
      end

      def handle_event(event, ctx, jsonl_file, txt_file)
        case event["type"]
        when "start" then ctx[:duration] = event["audio_duration_sec"]&.to_f
        when "eou" then handle_eou(event, ctx, jsonl_file, txt_file)
        when "final" then ctx[:final] = event
        end
      end

      def handle_eou(event, ctx, jsonl_file, txt_file)
        seg = event_to_segment(event, offset: ctx[:offset])
        jsonl_file.puts(JSON.generate(seg))
        txt_file.puts(format_segment(seg))
        RerunProgress.paint(event["audio_sec"]&.to_f, ctx)
      end

      def parse_event(line)
        line = line.strip
        return nil if line.empty?

        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def event_to_segment(event, offset: 0.0)
        speaker_id = event["speaker"]
        speaker = speaker_id ? "Speaker #{speaker_id}" : "Speaker 0"
        { "speaker" => speaker, "text" => event["text"].to_s,
          "start_time" => [(event["start_sec"].to_f + offset), 0.0].max,
          "end_time" => [(event["audio_sec"].to_f + offset), 0.0].max, "channel" => 0 }
      end

      def format_segment(seg)
        secs = seg["start_time"].to_i
        ts = format("%<h>02d:%<m>02d:%<s>02d", h: secs / 3600, m: (secs % 3600) / 60, s: secs % 60)
        "[#{ts}] #{seg["speaker"]}: #{seg["text"]}"
      end
    end
  end
end
