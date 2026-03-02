# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Cli
    class TranscribeTest < Minitest::Test
      test "run with --local aborts when whisper unavailable" do
        device = build_device
        whisper = Minitest::Mock.new
        whisper.expect(:available?, false)

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            error = assert_raises(SystemExit) { EarlScribe::Cli::Transcribe.run(["--local"]) }
            assert_equal 1, error.status
          end
        end
        whisper.verify
      end

      test "run without --local aborts without api key" do
        device = build_device
        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, nil) do
            error = assert_raises(SystemExit) { EarlScribe::Cli::Transcribe.run([]) }
            assert_equal 1, error.status
          end
        end
      end

      test "run_local warns when whisper available" do
        device = build_device
        whisper = Minitest::Mock.new
        whisper.expect(:available?, true)

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--local"]) }
            assert_includes stderr, "not yet fully implemented"
          end
        end
        whisper.verify
      end

      test "run with --device passes device name" do
        device = build_device
        resolved_name = nil
        resolver = lambda { |*args|
          resolved_name = args.first
          device
        }

        EarlScribe::Audio::Device.stub(:resolve, resolver) do
          EarlScribe::Config.stub(:deepgram_api_key, nil) do
            assert_raises(SystemExit) { EarlScribe::Cli::Transcribe.run(["--device", "Meeting"]) }
          end
        end
        assert_equal "Meeting", resolved_name
      end

      test "run_deepgram prints stereo banner and starts stream" do
        device = build_device
        client = build_mock_client
        capture = build_mock_capture

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Transcription::Deepgram.stub(:new, client) do
              EarlScribe::Audio::Capture.stub(:new, capture) do
                _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run([]) }
                assert_includes stderr, "stereo"
                assert_includes stderr, "Deepgram Nova-3"
              end
            end
          end
        end
      end

      test "run_deepgram with --mono prints mono banner" do
        device = build_device
        client = build_mock_client
        capture = build_mock_capture

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Transcription::Deepgram.stub(:new, client) do
              EarlScribe::Audio::Capture.stub(:new, capture) do
                _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--mono"]) }
                assert_includes stderr, "mono"
              end
            end
          end
        end
      end

      private

      def build_device
        EarlScribe::Audio::Device::DeviceInfo.new(index: 0, name: "TestMic")
      end

      def build_mock_client
        client = Object.new
        client.define_singleton_method(:connect) { |_cb| nil }
        client.define_singleton_method(:send_audio) { |_data| nil }
        client.define_singleton_method(:close) { nil }
        client
      end

      def build_mock_capture
        capture = Object.new
        capture.define_singleton_method(:start_streaming) { |&_block| nil }
        capture
      end
    end
  end
end
