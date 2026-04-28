# frozen_string_literal: true

module EarlScribe
  module Speaker
    # Matches audio embeddings against enrolled speakers using cosine similarity
    class Identifier
      DEFAULT_THRESHOLD = 0.75
      # Minimum gap between the best and second-best similarity for a match
      # to be considered confident. With acoustically-similar enrolled
      # voiceprints (same room/mic/call), the top-2 often both clear the
      # absolute threshold, so absolute-only matching produces false labels.
      DEFAULT_MARGIN = 0.04

      attr_reader :store, :threshold, :margin

      def initialize(store:, threshold: nil, margin: nil)
        @store = store
        @threshold = threshold || DEFAULT_THRESHOLD
        @margin = margin || DEFAULT_MARGIN
      end

      def identify(embedding)
        scores = scored_matches(embedding)
        return [nil, 0.0] if scores.empty?

        best, second = scores.first(2)
        return [nil, best[1]] if best[1] < threshold
        return [nil, best[1]] if second && (best[1] - second[1]) < margin

        best
      end

      private

      def scored_matches(embedding)
        scores = store.list.map do |name, data|
          [name, VectorMath.average_similarity(embedding, data["embeddings"])]
        end
        scores.sort_by { |_, sim| -sim }
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
