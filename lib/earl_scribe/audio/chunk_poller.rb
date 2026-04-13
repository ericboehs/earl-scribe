# frozen_string_literal: true

require "set"

module EarlScribe
  module Audio
    # Polls a directory for completed WAV chunks, yielding each exactly once.
    class ChunkPoller
      def initialize(output_dir)
        @output_dir = output_dir
        @yielded = Set.new
      end

      def poll(&block)
        loop do
          yield_completed_chunks(&block)
          sleep 0.5
        end
      end

      def yield_final_chunk(&block)
        Dir.glob(File.join(@output_dir, "*.wav")).sort.each do |path|
          next if @yielded.include?(path)

          block.call(path) if File.size?(path)
        end
      end

      private

      def yield_completed_chunks
        wavs = Dir.glob(File.join(@output_dir, "*.wav")).sort
        wavs[0...-1].each do |path|
          next if @yielded.include?(path)
          next unless File.size?(path)

          @yielded.add(path)
          yield path
        end
      end
    end
  end
end
