# frozen_string_literal: true

require "json"
require "fileutils"

module EarlScribe
  module Speaker
    # CRUD persistence for speaker voiceprints as JSON files
    class Store
      attr_reader :speakers_dir

      def initialize(speakers_dir: File.join(EarlScribe.config_root, "speakers"))
        @speakers_dir = speakers_dir
      end

      def list
        return {} unless Dir.exist?(speakers_dir)

        Dir.glob(File.join(speakers_dir, "*.json")).each_with_object({}) do |path, speakers|
          data = JSON.parse(File.read(path))
          speakers[data["name"]] = data
        end
      end

      def find(name)
        list[name]
      end

      def save(name, embeddings:, samples: [])
        FileUtils.mkdir_p(speakers_dir)
        data = { "name" => name, "embeddings" => embeddings, "samples" => samples }
        File.write(file_path(name), JSON.pretty_generate(data))
      end

      def delete(name)
        path = file_path(name)
        raise Error, "Speaker '#{name}' not found" unless File.exist?(path)

        File.delete(path)
      end

      private

      def file_path(name)
        safe_name = name.downcase.tr(" ", "_")
        File.join(speakers_dir, "#{safe_name}.json")
      end
    end
  end
end
