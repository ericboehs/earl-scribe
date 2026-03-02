# frozen_string_literal: true

require "open3"
require "json"

module EarlScribe
  module Speaker
    # Generates speaker embeddings by shelling out to a Python resemblyzer helper
    module Encoder
      HELPER_PATH = File.expand_path("../support/speaker_encoder.py", __dir__)

      def self.encode(wav_path)
        raise Error, "Audio file not found: #{wav_path}" unless File.exist?(wav_path)

        stdout, stderr, status = Open3.capture3("python3", HELPER_PATH, wav_path)
        raise Error, "Speaker encoder failed: #{stderr.strip}" unless status.success?

        JSON.parse(stdout)
      end

      def self.available?
        _stdout, _stderr, status = Open3.capture3("python3", "-c", "import resemblyzer")
        status.success?
      rescue Errno::ENOENT
        false
      end
    end
  end
end
