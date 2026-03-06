# frozen_string_literal: true

module EarlScribe
  module Cli
    # Handles interactive prompting for speaker identification during learn
    module LearnPrompter
      AUTO_CONFIRM_THRESHOLD = 0.85
      SUGGEST_THRESHOLD = 0.75

      def self.resolve_identity(label, embeddings, identifier, store)
        avg = average_embeddings(embeddings)
        name, similarity = identifier.identify(avg)

        if name && similarity >= AUTO_CONFIRM_THRESHOLD
          puts "  Auto-identified #{label} as #{name} (#{format("%.2f", similarity)})"
          enroll_speaker(name, embeddings, store)
          return name
        end

        yield
        prompt_for_identity(label, name, similarity, embeddings, store)
      end

      def self.prompt_for_identity(label, suggested_name, similarity, embeddings, store)
        if suggested_name && similarity >= SUGGEST_THRESHOLD
          return prompt_with_suggestion(suggested_name, similarity, embeddings, store)
        end

        prompt_open_ended(label, embeddings, store)
      end

      def self.prompt_with_suggestion(suggested_name, similarity, embeddings, store)
        print "  Suggested: #{suggested_name} (#{format("%.2f", similarity)}). Accept? [Y/n/name]: "
        input = $stdin.gets&.strip
        return enroll_and_return(suggested_name, embeddings, store) if accept_suggestion?(input)
        return if input&.casecmp("n")&.zero?

        enroll_and_return(input, embeddings, store)
      end

      def self.accept_suggestion?(input)
        input.nil? || input.empty? || input.casecmp("y").zero?
      end

      def self.prompt_open_ended(label, embeddings, store)
        print "  Who is #{label}? (name or 's' to skip): "
        input = $stdin.gets&.strip
        return if input.nil? || input.empty? || input.casecmp("s").zero?

        enroll_and_return(input, embeddings, store)
      end

      def self.enroll_and_return(name, embeddings, store)
        enroll_speaker(name, embeddings, store)
        name
      end

      def self.enroll_speaker(name, embeddings, store)
        existing = store.find(name) || { "embeddings" => [], "samples" => [] }
        all_embeddings = existing["embeddings"] + embeddings
        store.save(name, embeddings: all_embeddings, samples: existing["samples"])
        puts "  Enrolled #{name} (#{all_embeddings.size} total samples)"
      end

      def self.average_embeddings(embeddings)
        return embeddings.first if embeddings.size == 1

        embeddings.first.each_index.map do |i|
          embeddings.sum { |e| e[i] } / embeddings.size.to_f
        end
      end

      private_class_method :prompt_for_identity, :prompt_with_suggestion,
                           :accept_suggestion?, :prompt_open_ended,
                           :enroll_and_return, :enroll_speaker, :average_embeddings
    end
  end
end
