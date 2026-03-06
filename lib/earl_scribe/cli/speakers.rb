# frozen_string_literal: true

module EarlScribe
  module Cli
    # Manages speaker voiceprints: enroll, list, delete, identify, test
    module Speakers
      SUBCOMMANDS = %w[enroll list delete identify test learn].freeze

      USAGE = <<~TEXT
        Usage: earl-scribe speakers <subcommand>

        Subcommands:
          enroll "Name" file.wav   Enroll a speaker from audio samples
          list                      List enrolled speakers
          delete "Name"            Delete a speaker voiceprint
          identify file.wav         Identify the speaker in an audio file
          test file.wav             Show similarity scores for all speakers
          learn                     Learn speakers from past recordings
      TEXT

      def self.run(argv)
        subcommand = argv.first
        return warn(USAGE) unless SUBCOMMANDS.include?(subcommand)

        send("run_#{subcommand}", argv.drop(1))
      end

      def self.run_enroll(argv)
        name, *wav_paths = argv
        abort "Usage: earl-scribe speakers enroll \"Name\" file.wav [file2.wav ...]" unless name && wav_paths.any?

        existing = load_or_init_speaker(name)
        encode_samples(existing, wav_paths)
        save_enrollment(name, existing)
      end

      def self.load_or_init_speaker(name)
        Speaker::Store.new.find(name) || { "embeddings" => [], "samples" => [] }
      end

      def self.save_enrollment(name, data)
        embeddings = data["embeddings"]
        Speaker::Store.new.save(name, embeddings: embeddings, samples: data["samples"])
        puts "Enrolled '#{name}' with #{embeddings.size} sample(s)"
      end

      def self.encode_samples(existing, wav_paths)
        embeddings, samples = existing.values_at("embeddings", "samples")
        wav_paths.each { |path| encode_one_sample(embeddings, samples, path) }
      end

      def self.encode_one_sample(embeddings, samples, path)
        abort "File not found: #{path}" unless File.exist?(path)
        warn "Processing: #{path}"
        embeddings << Speaker::Encoder.encode(path)
        samples << File.expand_path(path)
      end

      def self.run_list(_argv)
        speakers = Speaker::Store.new.list
        if speakers.empty?
          return puts("No speakers enrolled.\nEnroll with: earl-scribe speakers enroll \"Name\" audio.wav")
        end

        puts "Enrolled speakers:\n\n"
        speakers.each_value { |data| print_speaker(data) }
      end

      def self.print_speaker(data)
        count = data["embeddings"].size
        puts "  #{data["name"]} (#{count} sample#{"s" unless count == 1})"
        data.fetch("samples", []).each { |sample| puts "    - #{sample}" }
      end

      def self.run_delete(argv)
        name = argv.first
        abort "Usage: earl-scribe speakers delete \"Name\"" unless name

        Speaker::Store.new.delete(name)
        puts "Deleted '#{name}'"
      end

      def self.run_identify(argv)
        wav_path = argv.first
        abort "Usage: earl-scribe speakers identify audio.wav" unless wav_path

        name, similarity = identify_speaker(wav_path)
        print_identification(name, similarity)
      end

      def self.identify_speaker(wav_path)
        embedding = Speaker::Encoder.encode(wav_path)
        Speaker::Identifier.new(store: Speaker::Store.new).identify(embedding)
      end

      def self.print_identification(name, similarity)
        sim_str = format("%.3f", similarity)
        puts name ? "#{name} (similarity: #{sim_str})" : "Unknown speaker (best similarity: #{sim_str})"
      end

      def self.run_test(argv)
        wav_path = argv.first
        abort "Usage: earl-scribe speakers test audio.wav" unless wav_path

        embedding = Speaker::Encoder.encode(wav_path)
        print_scores(embedding)
      end

      def self.print_scores(embedding)
        speakers = Speaker::Store.new.list
        abort "No speakers enrolled." if speakers.empty?

        puts "Similarity scores:\n\n"
        speakers.each_value { |data| print_score_line(data, embedding) }
      end

      def self.print_score_line(data, embedding)
        sim = Speaker::VectorMath.average_similarity(embedding, data["embeddings"])
        marker = sim >= Speaker::Identifier::DEFAULT_THRESHOLD ? " <-- MATCH" : ""
        puts format("  %-20<name>s avg=%<sim>.3f%<marker>s", name: data["name"], sim: sim, marker: marker)
      end

      def self.run_learn(argv)
        Learn.run(argv)
      end

      private_class_method :load_or_init_speaker, :save_enrollment,
                           :encode_samples, :encode_one_sample,
                           :print_speaker, :identify_speaker, :print_identification,
                           :print_scores, :print_score_line,
                           :run_enroll, :run_list, :run_delete, :run_identify, :run_test,
                           :run_learn
    end
  end
end
