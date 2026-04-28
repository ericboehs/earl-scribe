# frozen_string_literal: true

module EarlScribe
  module Cli
    module TranscribeSession
      SessionContext = Struct.new(:capture, :writer, :jsonl, :meeting, :paths, :term_display, keyword_init: true)

      def self.build(device, options, channels: 1)
        meeting = Calendar.current_meeting
        title = options[:title] || meeting&.dig(:title)
        record = options[:record] || options[:rerun]
        paths = Transcription::TranscriptWriter.build_paths(record: record, meeting_title: title)
        SessionContext.new(
          capture: build_capture(device, options, channels, paths[:recording]),
          writer: Transcription::TranscriptWriter.new(paths[:transcript]),
          jsonl: build_jsonl_writer(paths[:jsonl], title, meeting),
          meeting: meeting, paths: paths
        )
      end

      def self.build_capture(device, options, channels, recording_path)
        return NullCapture.new if options[:native]
        return build_device_capture(device, channels, recording_path) if device
        return build_audiotee_capture(channels, recording_path) if options[:no_mic]

        build_dual_capture(options[:mic], channels, recording_path, mic_gain_db: options[:mic_gain_db])
      end

      # No-op capture stub for --native mode where the Swift shim owns audio capture.
      class NullCapture
        def channels
          1
        end

        def sample_rate
          16_000
        end

        def start_streaming
          nil
        end
      end

      def self.build_device_capture(device, channels, recording_path)
        Audio::Capture.new(device_index: device.index, device_name: device.name, channels: channels,
                           sample_rate: Config.audio_sample_rate, recording_path: recording_path)
      end

      def self.build_audiotee_capture(channels, recording_path)
        Audio::AudioTee.new(channels: channels, sample_rate: Config.audio_sample_rate,
                            recording_path: recording_path)
      end

      def self.build_dual_capture(mic, channels, recording_path, mic_gain_db: nil)
        Audio::DualCapture.new(mic_device: mic, channels: channels,
                               sample_rate: Config.audio_sample_rate, recording_path: recording_path,
                               mic_gain_db: mic_gain_db)
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
        ctx.writer.close
        ctx.jsonl.close
        regenerate_transcript(ctx.paths)
        print_session_summary(ctx.paths)
      end

      def self.regenerate_transcript(paths)
        return unless paths[:jsonl] && File.exist?(paths[:jsonl])

        reader = Transcription::JsonlReader.new(paths[:jsonl])
        File.open(paths[:transcript], "w") do |file|
          reader.segments.each { |seg| file.puts(seg.to_timestamped_s) }
        end
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

      private_class_method :build_capture, :build_device_capture, :build_audiotee_capture,
                           :build_dual_capture, :build_jsonl_writer, :regenerate_transcript,
                           :print_session_summary, :append_path
    end
  end
end
