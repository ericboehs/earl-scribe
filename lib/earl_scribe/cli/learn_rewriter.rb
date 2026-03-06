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
        lines = File.readlines(path).map do |line|
          data = JSON.parse(line)
          if data["speaker"] && updates[data["speaker"]]
            data["speaker"] = updates[data["speaker"]]
            JSON.generate(data)
          else
            line.chomp
          end
        end
        File.write(path, lines.map { |l| "#{l}\n" }.join)
      end

      def self.rewrite_transcript(txt_path, jsonl_path)
        reader = Transcription::JsonlReader.new(jsonl_path)
        File.open(txt_path, "w") do |f|
          reader.segments.each { |seg| f.puts(seg.to_s) }
        end
      end

      private_class_method :rewrite_jsonl, :rewrite_transcript
    end
  end
end
