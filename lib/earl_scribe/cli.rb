# frozen_string_literal: true

require_relative "cli/transcribe"
require_relative "cli/speakers"
require_relative "cli/devices"

module EarlScribe
  # CLI dispatcher routing subcommands to handlers
  module Cli
    COMMANDS = {
      "transcribe" => Cli::Transcribe,
      "speakers" => Cli::Speakers,
      "devices" => Cli::Devices
    }.freeze

    USAGE = <<~TEXT
      Usage: earl-scribe <command> [options]

      Commands:
        transcribe   Transcribe meeting audio (Deepgram or local whisper.cpp)
        speakers     Manage speaker voiceprints (enroll/list/delete/identify/test)
        devices      List available audio devices

      Run earl-scribe <command> --help for details
    TEXT

    def self.run(argv)
      handler = COMMANDS[argv.first]

      if handler
        handler.run(argv.drop(1))
      else
        warn USAGE
      end
    end
  end
end
