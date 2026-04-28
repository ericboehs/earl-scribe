# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Tees transcript output to both stdout and a file, flushing after each line.
    class TranscriptWriter
      def self.build_paths(record:, meeting_title: nil)
        dir = EarlScribe.data_dir
        base = base_for(meeting_title)
        path = ->(suffix) { File.join(dir, "#{base}#{suffix}") }
        { transcript: path.call(".txt"), jsonl: path.call(".jsonl"),
          transcript_live: path.call("-live.txt"), jsonl_live: path.call("-live.jsonl"),
          wav: path.call(".wav"), recording: record ? path.call(".m4a") : nil }
      end

      def self.base_for(meeting_title)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        slug = meeting_title && slugify(meeting_title)
        slug ? "#{timestamp}-#{slug}" : "earl-scribe-#{timestamp}"
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
