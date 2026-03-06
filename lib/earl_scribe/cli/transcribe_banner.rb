# frozen_string_literal: true

module EarlScribe
  module Cli
    # Prints the startup banner for transcription sessions
    module TranscribeBanner
      def self.print(device, engine:, mode:, id_status:, session: {})
        warn build_lines(device, engine, mode, id_status, session)
      end

      def self.build_lines(device, engine, mode, id_status, session)
        lines = +"=== Meeting Transcription (#{engine}) ===\n"
        session[:meeting_title]&.tap { |title| lines << "Meeting:    #{title}\n" }
        lines << "Device:     [#{device.index}] #{device.name}\n"
        lines << "Mode:       #{mode}\n"
        lines << "Speaker ID: #{id_status}\n"
        session[:transcript]&.tap { |path| lines << "Transcript: #{path}\n" }
        session[:recording]&.tap { |path| lines << "Recording:  #{path}\n" }
        lines << "\nRecording... Press Ctrl+C to stop.\n---\n"
      end

      private_class_method :build_lines
    end
  end
end
