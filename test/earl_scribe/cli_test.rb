# frozen_string_literal: true

require "test_helper"

module EarlScribe
  class CliTest < Minitest::Test
    test "run dispatches to transcribe" do
      called = false
      EarlScribe::Cli::Transcribe.stub(:run, ->(_argv) { called = true }) do
        EarlScribe::Cli.run(["transcribe"])
      end
      assert called
    end

    test "run dispatches to speakers" do
      called = false
      EarlScribe::Cli::Speakers.stub(:run, ->(_argv) { called = true }) do
        EarlScribe::Cli.run(["speakers"])
      end
      assert called
    end

    test "run dispatches to devices" do
      called = false
      EarlScribe::Cli::Devices.stub(:run, ->(_argv) { called = true }) do
        EarlScribe::Cli.run(["devices"])
      end
      assert called
    end

    test "run prints usage for unknown command" do
      output = capture_io { EarlScribe::Cli.run(["unknown"]) }
      assert_includes output[1], "Usage: earl-scribe"
    end

    test "run prints usage for no arguments" do
      output = capture_io { EarlScribe::Cli.run([]) }
      assert_includes output[1], "Usage: earl-scribe"
    end

    test "passes remaining args to handler" do
      received_args = nil
      EarlScribe::Cli::Transcribe.stub(:run, ->(argv) { received_args = argv }) do
        EarlScribe::Cli.run(["transcribe", "--mono", "--device", "Test"])
      end
      assert_equal ["--mono", "--device", "Test"], received_args
    end
  end
end
