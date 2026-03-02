# frozen_string_literal: true

module EarlScribe
  module Cli
    # Prints the startup banner for transcription sessions
    module TranscribeBanner
      def self.print(device, engine:, mode:, id_status:, recording: nil)
        lines = +"=== Meeting Transcription (#{engine}) ===\n"
        lines << "Device:     [#{device.index}] #{device.name}\n"
        lines << "Mode:       #{mode}\n"
        lines << "Speaker ID: #{id_status}\n"
        lines << "Recording:  #{recording}\n" if recording
        lines << "\nRecording... Press Ctrl+C to stop.\n---\n"
        warn lines
      end
    end
  end
end
