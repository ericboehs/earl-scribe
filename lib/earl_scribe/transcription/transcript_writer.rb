# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Tees transcript output to both stdout and a file, flushing after each line.
    class TranscriptWriter
      def self.build_paths(record:)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        dir = EarlScribe.data_dir
        transcript = File.join(dir, "earl-scribe-#{timestamp}.txt")
        recording = record ? File.join(dir, "earl-scribe-#{timestamp}.m4a") : nil
        [transcript, recording]
      end

      def initialize(path)
        FileUtils.mkdir_p(File.dirname(path))
        @path = path
        @closed = false
      end

      def write_line(text)
        puts text
        return if @closed

        File.open(@path, "a") { |file| file.puts(text) }
      rescue SystemCallError => error
        @closed = true
        warn "WARNING: Transcript write failed: #{error.message}. Continuing with stdout only."
      end

      def close
        @closed = true
      end
    end
  end
end
