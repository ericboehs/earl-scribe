# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Transcription
    class HallucinationFilterTest < Minitest::Test
      test "detects BLANK_AUDIO" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("[BLANK_AUDIO]")
      end

      test "detects repeated You" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("You. You. You.")
      end

      test "detects Thank you repetitions" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("Thank you. Thank you.")
      end

      test "detects Thanks for watching" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("Thanks for watching!")
      end

      test "detects repeated Bye" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("Bye. Bye.")
      end

      test "detects repeated Okay" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("Okay. Okay.")
      end

      test "detects repeated Oh" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("Oh. Oh.")
      end

      test "detects repeated So" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("So. So.")
      end

      test "detects dots only" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("...")
      end

      test "detects punctuation only" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?(".,! ,")
      end

      test "detects empty string" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("")
      end

      test "detects whitespace only" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("   ")
      end

      test "detects nil" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?(nil)
      end

      test "clean text passes through" do
        text = "Hello everyone, welcome to the meeting."
        assert_not EarlScribe::Transcription::HallucinationFilter.hallucination?(text)
      end

      test "filter returns nil for hallucination" do
        assert_nil EarlScribe::Transcription::HallucinationFilter.filter("[BLANK_AUDIO]")
      end

      test "filter returns stripped text for clean input" do
        result = EarlScribe::Transcription::HallucinationFilter.filter("  Hello world  ")
        assert_equal "Hello world", result
      end

      test "filter returns nil for empty string" do
        assert_nil EarlScribe::Transcription::HallucinationFilter.filter("")
      end

      test "case insensitive detection" do
        assert EarlScribe::Transcription::HallucinationFilter.hallucination?("[blank_audio]")
      end
    end
  end
end
