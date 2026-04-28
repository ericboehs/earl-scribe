# frozen_string_literal: true

require "json"

module EarlScribe
  module Cli
    # Rewrites JSONL and transcript files with resolved speaker names
    module LearnRewriter
      def self.rewrite(rec, updates)
        rewrite_jsonl(rec[:jsonl_path], updates)
        rewrite_transcript(rec[:jsonl_path].sub(/\.jsonl\z/, ".txt"), rec[:jsonl_path])
        puts "  Updated transcript files with resolved speaker names."
      end

      def self.rewrite_jsonl(path, updates)
        lines = File.readlines(path).map { |line| rewrite_line(line, updates) }
        File.write(path, lines.map { |l| "#{l}\n" }.join)
      end

      def self.rewrite_line(line, updates)
        data = JSON.parse(line)
        new_speaker = updates[data["speaker"]]
        return line.chomp unless new_speaker && data["speaker"] != new_speaker

        data["speaker"] = new_speaker
        JSON.generate(data)
      end

      def self.rewrite_transcript(txt_path, jsonl_path)
        reader = Transcription::JsonlReader.new(jsonl_path)
        File.open(txt_path, "w") do |f|
          reader.segments.each { |seg| f.puts(seg.to_timestamped_s) }
        end
      end

      private_class_method :rewrite_jsonl, :rewrite_transcript
    end
  end
end
