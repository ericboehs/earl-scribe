# frozen_string_literal: true

require "json"

module EarlScribe
  module Transcription
    # Appends structured JSONL transcript data alongside the plain-text transcript
    class JsonlWriter
      def initialize(path)
        FileUtils.mkdir_p(File.dirname(path))
        @path = path
        @closed = false
      end

      def write_metadata(hash)
        write_json({ type: "metadata" }.merge(hash))
      end

      def write_segment(result)
        write_json(result.to_h)
      end

      def close
        @closed = true
      end

      private

      def write_json(hash)
        return if @closed

        File.open(@path, "a") { |f| f.puts(JSON.generate(hash)) }
      rescue SystemCallError => error
        @closed = true
        warn "WARNING: JSONL write failed: #{error.message}. Continuing without structured output."
      end
    end
  end
end
