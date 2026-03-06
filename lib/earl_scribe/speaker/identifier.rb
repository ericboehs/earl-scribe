# frozen_string_literal: true

module EarlScribe
  module Speaker
    # Matches audio embeddings against enrolled speakers using cosine similarity
    class Identifier
      DEFAULT_THRESHOLD = 0.75

      attr_reader :store, :threshold

      def initialize(store:, threshold: nil)
        @store = store
        @threshold = threshold || DEFAULT_THRESHOLD
      end

      def identify(embedding)
        best_name, best_sim = best_match(embedding)
        return [best_name, best_sim] if best_sim >= threshold

        [nil, best_sim]
      end

      private

      def best_match(embedding)
        top_score = store.list.map { |name, data| [name, VectorMath.average_similarity(embedding, data["embeddings"])] }
                              .max_by { |_name, sim| sim }
        top_score || [nil, 0.0]
      end
    end

    # Pure vector math operations for speaker embedding comparison
    module VectorMath
      def self.cosine_similarity(vec_a, vec_b)
        dot = dot_product(vec_a, vec_b)
        magnitude = Math.sqrt(sum_of_squares(vec_a)) * Math.sqrt(sum_of_squares(vec_b))
        return 0.0 if magnitude.zero?

        dot / magnitude
      end

      def self.average_similarity(embedding, stored_embeddings)
        stored_embeddings.sum { |stored| cosine_similarity(embedding, stored) } / stored_embeddings.size.to_f
      end

      def self.dot_product(vec_a, vec_b)
        vec_a.zip(vec_b).sum { |val_a, val_b| val_a * val_b }
      end

      def self.sum_of_squares(vec)
        vec.sum { |val| val * val }
      end

      private_class_method :dot_product, :sum_of_squares
    end
  end
end
