# frozen_string_literal: true

module EarlScribe
  module Cli
    # Wraps writers, capture, and metadata for a transcription session
    module TranscribeSession
      SessionContext = Struct.new(:capture, :writer, :jsonl, :meeting, :paths, :term_display, keyword_init: true)

      def self.build(device, options, channels: 1)
        meeting = Calendar.current_meeting
        paths = Transcription::TranscriptWriter.build_paths(
          record: options[:record], meeting_title: meeting&.dig(:title)
        )
        SessionContext.new(
          capture: build_capture(device, channels, paths[:recording]),
          writer: Transcription::TranscriptWriter.new(paths[:transcript]),
          jsonl: build_jsonl_writer(paths[:jsonl], meeting),
          meeting: meeting, paths: paths
        )
      end

      def self.build_capture(device, channels, recording_path)
        Audio::Capture.new(device_index: device.index, channels: channels, recording_path: recording_path)
      end

      def self.build_jsonl_writer(path, meeting)
        jsonl = Transcription::JsonlWriter.new(path)
        meta = { recorded_at: Time.now.iso8601 }
        meta.merge!(meeting_title: meeting[:title], meeting_id: meeting[:id]) if meeting
        jsonl.write_metadata(meta)
        jsonl
      end

      def self.close_writers(ctx)
        (f = ctx.term_display&.flush) && ctx.writer.write_line(f.to_s)
        ctx.writer.close
        ctx.jsonl.close
      end

      def self.session_info(ctx)
        { meeting_title: ctx.meeting&.dig(:title),
          transcript: ctx.paths[:transcript], recording: ctx.paths[:recording] }
      end

      private_class_method :build_capture, :build_jsonl_writer
    end
  end
end
