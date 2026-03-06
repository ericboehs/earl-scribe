# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Tees transcript output to both stdout and a file, flushing after each line.
    class TranscriptWriter
      def self.build_paths(record:, meeting_title: nil)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        dir = EarlScribe.data_dir
        slug = meeting_title && slugify(meeting_title)
        base = slug ? "#{timestamp}-#{slug}" : "earl-scribe-#{timestamp}"
        {
          transcript: File.join(dir, "#{base}.txt"),
          jsonl: File.join(dir, "#{base}.jsonl"),
          recording: record ? File.join(dir, "#{base}.m4a") : nil
        }
      end

      def initialize(path)
        FileUtils.mkdir_p(File.dirname(path))
        @path = path
        @closed = false
      end

      def write_line(text)
        return if @closed

        File.open(@path, "a") { |file| file.puts(text) }
      rescue SystemCallError => error
        @closed = true
        warn "WARNING: Transcript write failed: #{error.message}. Continuing without file output."
      end

      def close
        @closed = true
      end

      def self.slugify(title)
        title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")[0, 60]
      end

      private_class_method :slugify
    end
  end
end
