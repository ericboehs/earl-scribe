# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Speaker
    class VectorMathTest < Minitest::Test
      test "cosine_similarity of identical vectors is 1.0" do
        vec = [1.0, 2.0, 3.0]
        assert_in_delta 1.0, EarlScribe::Speaker::VectorMath.cosine_similarity(vec, vec)
      end

      test "cosine_similarity of orthogonal vectors is 0.0" do
        vec_a = [1.0, 0.0]
        vec_b = [0.0, 1.0]
        assert_in_delta 0.0, EarlScribe::Speaker::VectorMath.cosine_similarity(vec_a, vec_b)
      end

      test "cosine_similarity of opposite vectors is -1.0" do
        vec_a = [1.0, 2.0, 3.0]
        vec_b = [-1.0, -2.0, -3.0]
        assert_in_delta(-1.0, EarlScribe::Speaker::VectorMath.cosine_similarity(vec_a, vec_b))
      end

      test "cosine_similarity returns 0 for zero vector" do
        vec_a = [0.0, 0.0, 0.0]
        vec_b = [1.0, 2.0, 3.0]
        assert_in_delta 0.0, EarlScribe::Speaker::VectorMath.cosine_similarity(vec_a, vec_b)
      end

      test "average_similarity computes mean of cosine similarities" do
        embedding = [1.0, 0.0]
        stored = [[1.0, 0.0], [0.0, 1.0]]
        avg = EarlScribe::Speaker::VectorMath.average_similarity(embedding, stored)

        # cos([1,0], [1,0]) = 1.0, cos([1,0], [0,1]) = 0.0, avg = 0.5
        assert_in_delta 0.5, avg
      end

      test "cosine_similarity handles different magnitude vectors" do
        vec_a = [1.0, 0.0]
        vec_b = [100.0, 0.0]
        assert_in_delta 1.0, EarlScribe::Speaker::VectorMath.cosine_similarity(vec_a, vec_b)
      end
    end
  end
end
