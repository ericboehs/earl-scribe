# frozen_string_literal: true

module EarlScribe
  module Cli
    # Wraps writers, capture, and metadata for a transcription session
    module TranscribeSession
      SessionContext = Struct.new(:capture, :writer, :jsonl, :meeting, :paths, :term_display, keyword_init: true)

      def self.build(device, options, channels: 1)
        meeting = Calendar.current_meeting
        title = options[:title] || meeting&.dig(:title)
        paths = Transcription::TranscriptWriter.build_paths(record: options[:record], meeting_title: title)
        SessionContext.new(
          capture: build_capture(device, channels, paths[:recording]),
          writer: Transcription::TranscriptWriter.new(paths[:transcript]),
          jsonl: build_jsonl_writer(paths[:jsonl], title, meeting),
          meeting: meeting, paths: paths
        )
      end

      def self.build_capture(device, channels, recording_path)
        return build_audiotee_capture(channels, recording_path) unless device

        Audio::Capture.new(device_index: device.index, device_name: device.name, channels: channels,
                           sample_rate: Config.audio_sample_rate, recording_path: recording_path)
      end

      def self.build_audiotee_capture(channels, recording_path)
        Audio::AudioTee.new(channels: channels, sample_rate: Config.audio_sample_rate,
                            recording_path: recording_path)
      end

      def self.build_jsonl_writer(path, title, meeting)
        jsonl = Transcription::JsonlWriter.new(path)
        meta = { recorded_at: Time.now.iso8601 }
        meta[:meeting_title] = title if title
        meta[:meeting_id] = meeting[:id] if meeting&.dig(:id)
        jsonl.write_metadata(meta)
        jsonl
      end

      def self.close_writers(ctx)
        flushed = ctx.term_display&.flush
        writer = ctx.writer
        writer.write_line(flushed.to_timestamped_s) if flushed
        writer.close
        ctx.jsonl.close
        print_session_summary(ctx.paths)
      end

      def self.print_session_summary(paths)
        lines = +"\n---\n"
        append_path(lines, "Transcript:", paths[:transcript])
        append_path(lines, "Recording: ", paths[:recording])
        warn lines
      end

      def self.append_path(lines, label, path)
        lines << "#{label} #{path}\n" if path && File.exist?(path)
      end

      def self.session_info(ctx, meeting_title:)
        { meeting_title: meeting_title,
          transcript: ctx.paths[:transcript], recording: ctx.paths[:recording] }
      end

      private_class_method :build_capture, :build_audiotee_capture, :build_jsonl_writer,
                           :print_session_summary, :append_path
    end
  end
end
