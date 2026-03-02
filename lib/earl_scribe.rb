# frozen_string_literal: true

require "logger"
require "fileutils"

require_relative "earl_scribe/version"
require_relative "earl_scribe/config"
require_relative "earl_scribe/audio/device"
require_relative "earl_scribe/audio/capture"
require_relative "earl_scribe/transcription/result"
require_relative "earl_scribe/transcription/hallucination_filter"
require_relative "earl_scribe/transcription/result_parser"
require_relative "earl_scribe/transcription/word_grouper"
require_relative "earl_scribe/transcription/deepgram"
require_relative "earl_scribe/transcription/whisper"
require_relative "earl_scribe/speaker/store"
require_relative "earl_scribe/speaker/encoder"
require_relative "earl_scribe/speaker/identifier"
require_relative "earl_scribe/cli"

# Meeting transcription CLI with Deepgram streaming and whisper.cpp
module EarlScribe
  # Base error class for EarlScribe exceptions
  class Error < StandardError; end

  def self.config_root
    File.join(Dir.home, ".config", "earl-scribe")
  end

  def self.logger
    @logger ||= Logger.new($stderr, level: Logger::INFO)
  end

  def self.logger=(new_logger)
    @logger = new_logger
  end
end
