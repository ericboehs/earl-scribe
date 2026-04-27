# frozen_string_literal: true

module EarlScribe
  module Cli
    module TranscribeSummarizer
      def self.build(ctx, opts)
        return nil unless opts[:summarize]

        summarizer = Summarizer::Qwen.new
        unless summarizer.available?
          warn "earl-scribe: summarizer disabled — #{summarizer.unavailable_reason}"
          return nil
        end

        Summarizer::Scheduler.new(
          transcript_source: build_transcript_source(ctx),
          summarizer: summarizer,
          output_path: summary_path_for(ctx),
          interval_sec: opts[:summary_interval_sec]
        )
      end

      def self.build_transcript_source(ctx)
        path = ctx.paths[:transcript]
        -> { File.read(path) if File.exist?(path) }
      end

      def self.summary_path_for(ctx)
        path = ctx.paths[:transcript]
        ext = File.extname(path)
        "#{path.delete_suffix(ext)}-summary.md"
      end

      private_class_method :build_transcript_source, :summary_path_for
    end
  end
end
