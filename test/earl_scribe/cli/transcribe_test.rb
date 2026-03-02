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

      test "run_local transcribes chunks and prints output" do
        device = build_device
        whisper = build_mock_whisper(available: true, text: "Hello world")
        mock_capture = build_mock_chunked_capture(["/tmp/chunk1.wav"])

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            EarlScribe::Audio::Capture.stub(:new, mock_capture) do
              EarlScribe::Speaker::Encoder.stub(:available?, false) do
                stdout, _stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--local"]) }
                assert_includes stdout, "Hello world"
              end
            end
          end
        end
      end

      test "run_local skips hallucinated chunks" do
        device = build_device
        whisper = build_mock_whisper(available: true, text: nil)
        mock_capture = build_mock_chunked_capture(["/tmp/chunk1.wav"])

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            EarlScribe::Audio::Capture.stub(:new, mock_capture) do
              EarlScribe::Speaker::Encoder.stub(:available?, false) do
                stdout, _stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--local"]) }
                assert_equal "", stdout
              end
            end
          end
        end
      end

      test "run_local with --no-identify skips speaker identification" do
        device = build_device
        whisper = build_mock_whisper(available: true, text: "Test output")
        mock_capture = build_mock_chunked_capture(["/tmp/chunk1.wav"])

        encoder_called = false
        encoder_stub = lambda { |_path|
          encoder_called = true
          []
        }

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            EarlScribe::Audio::Capture.stub(:new, mock_capture) do
              EarlScribe::Speaker::Encoder.stub(:available?, true) do
                EarlScribe::Speaker::Encoder.stub(:encode, encoder_stub) do
                  stdout, _stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--local", "--no-identify"]) }
                  assert_includes stdout, "Test output"
                  assert_not encoder_called, "Expected Encoder.encode not to be called"
                end
              end
            end
          end
        end
      end

      test "run_local with speaker identification prints speaker name" do
        device = build_device
        whisper = build_mock_whisper(available: true, text: "Great point")
        mock_capture = build_mock_chunked_capture(["/tmp/chunk1.wav"])

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            EarlScribe::Audio::Capture.stub(:new, mock_capture) do
              EarlScribe::Speaker::Encoder.stub(:available?, true) do
                EarlScribe::Speaker::Encoder.stub(:encode, ->(_p) { [0.1, 0.2] }) do
                  EarlScribe::Speaker::Identifier.stub(:new, build_mock_identifier("Alice")) do
                    stdout, _stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--local"]) }
                    assert_includes stdout, "Alice: Great point"
                  end
                end
              end
            end
          end
        end
      end

      test "run_local prints whisper.cpp banner" do
        device = build_device
        whisper = build_mock_whisper(available: true, text: nil)
        mock_capture = build_mock_chunked_capture([])

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            EarlScribe::Audio::Capture.stub(:new, mock_capture) do
              EarlScribe::Speaker::Encoder.stub(:available?, false) do
                _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--local"]) }
                assert_includes stderr, "whisper.cpp"
                assert_includes stderr, "TestMic"
              end
            end
          end
        end
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
        capture = build_mock_streaming_capture("data")

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, false) do
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
      end

      test "run_deepgram with --mono prints mono banner" do
        device = build_device
        client = build_mock_client
        capture = build_mock_capture

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, false) do
              EarlScribe::Transcription::Deepgram.stub(:new, client) do
                EarlScribe::Audio::Capture.stub(:new, capture) do
                  _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--mono"]) }
                  assert_includes stderr, "mono"
                end
              end
            end
          end
        end
      end

      test "run_deepgram with speaker ID enabled tees data to PcmBuffer" do
        device = build_device
        client = build_mock_client
        buffer_data = []
        capture = build_mock_streaming_capture("audio_chunk")

        mock_resolver = build_mock_resolver(buffer_data)

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, true) do
              EarlScribe::Speaker::SessionResolver.stub(:new, mock_resolver) do
                EarlScribe::Transcription::Deepgram.stub(:new, client) do
                  EarlScribe::Audio::Capture.stub(:new, capture) do
                    capture_io { EarlScribe::Cli::Transcribe.run([]) }
                  end
                end
              end
            end
          end
        end

        assert_equal ["audio_chunk"], buffer_data
      end

      test "run_deepgram with --no-identify skips resolver creation" do
        device = build_device
        client = build_mock_client
        capture = build_mock_capture

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, true) do
              EarlScribe::Transcription::Deepgram.stub(:new, client) do
                EarlScribe::Audio::Capture.stub(:new, capture) do
                  _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--no-identify"]) }
                  assert_includes stderr, "Speaker ID: disabled"
                end
              end
            end
          end
        end
      end

      test "run_deepgram with resolver replaces speaker labels in output" do
        device = build_device
        captured_callback = nil
        client = Object.new
        client.define_singleton_method(:connect) { |cb| captured_callback = cb }
        client.define_singleton_method(:send_audio) { |_data| nil }
        client.define_singleton_method(:close) { nil }

        mock_resolver = Object.new
        mock_resolver.define_singleton_method(:pcm_buffer) { nil }
        mock_resolver.define_singleton_method(:resolve_label) { |_id, _w| "Alice" }
        mock_resolver.define_singleton_method(:shutdown) { nil }

        capture = build_mock_streaming_capture("data")

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, true) do
              EarlScribe::Speaker::SessionResolver.stub(:new, mock_resolver) do
                EarlScribe::Transcription::Deepgram.stub(:new, client) do
                  EarlScribe::Audio::Capture.stub(:new, capture) do
                    capture_io { EarlScribe::Cli::Transcribe.run([]) }
                  end
                end
              end
            end
          end
        end

        words = [{ "word" => "hi", "punctuated_word" => "Hi", "speaker" => 0, "start" => 0.0, "end" => 0.5 }]
        stdout, _stderr = capture_io { captured_callback.call({ words: words }) }
        assert_includes stdout, "Alice: Hi"
      end

      test "run_deepgram without resolver outputs default Speaker N labels" do
        device = build_device
        captured_callback = nil
        client = Object.new
        client.define_singleton_method(:connect) { |cb| captured_callback = cb }
        client.define_singleton_method(:send_audio) { |_data| nil }
        client.define_singleton_method(:close) { nil }

        capture = build_mock_capture

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, false) do
              EarlScribe::Transcription::Deepgram.stub(:new, client) do
                EarlScribe::Audio::Capture.stub(:new, capture) do
                  capture_io { EarlScribe::Cli::Transcribe.run([]) }
                end
              end
            end
          end
        end

        words = [{ "word" => "hi", "punctuated_word" => "Hi", "speaker" => 0, "start" => 0.0, "end" => 0.5 }]
        stdout, _stderr = capture_io { captured_callback.call({ words: words }) }
        assert_includes stdout, "Speaker 0: Hi"
      end

      test "run_deepgram handles interrupt with resolver" do
        device = build_device
        client = build_mock_client
        shutdown_called = false
        mock_resolver = build_mock_resolver([])
        mock_resolver.define_singleton_method(:shutdown) { shutdown_called = true }

        interrupt_capture = Object.new
        interrupt_capture.define_singleton_method(:channels) { 2 }
        interrupt_capture.define_singleton_method(:start_streaming) { |&_block| raise Interrupt }

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, true) do
              EarlScribe::Speaker::SessionResolver.stub(:new, mock_resolver) do
                EarlScribe::Transcription::Deepgram.stub(:new, client) do
                  EarlScribe::Audio::Capture.stub(:new, interrupt_capture) do
                    capture_io { EarlScribe::Cli::Transcribe.run([]) }
                  end
                end
              end
            end
          end
        end

        assert shutdown_called
      end

      test "run_deepgram handles interrupt without resolver" do
        device = build_device
        client = build_mock_client
        close_called = false
        client.define_singleton_method(:close) { close_called = true }

        interrupt_capture = Object.new
        interrupt_capture.define_singleton_method(:channels) { 2 }
        interrupt_capture.define_singleton_method(:start_streaming) { |&_block| raise Interrupt }

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, false) do
              EarlScribe::Transcription::Deepgram.stub(:new, client) do
                EarlScribe::Audio::Capture.stub(:new, interrupt_capture) do
                  capture_io { EarlScribe::Cli::Transcribe.run([]) }
                end
              end
            end
          end
        end

        assert close_called
      end

      test "run_deepgram with --record shows recording path in banner" do
        device = build_device
        client = build_mock_client
        capture = build_mock_capture

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, false) do
              EarlScribe::Transcription::Deepgram.stub(:new, client) do
                EarlScribe::Audio::Capture.stub(:new, capture) do
                  _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--record"]) }
                  assert_includes stderr, "Recording:  earl-scribe-"
                  assert_includes stderr, ".m4a"
                end
              end
            end
          end
        end
      end

      test "run_deepgram without --record omits recording line" do
        device = build_device
        client = build_mock_client
        capture = build_mock_capture

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, false) do
              EarlScribe::Transcription::Deepgram.stub(:new, client) do
                EarlScribe::Audio::Capture.stub(:new, capture) do
                  _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run([]) }
                  assert_not_includes stderr, "Recording:"
                end
              end
            end
          end
        end
      end

      test "run_local with --record shows recording path in banner" do
        device = build_device
        whisper = build_mock_whisper(available: true, text: nil)
        mock_capture = build_mock_chunked_capture([])

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            EarlScribe::Audio::Capture.stub(:new, mock_capture) do
              EarlScribe::Speaker::Encoder.stub(:available?, false) do
                _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--local", "--record"]) }
                assert_includes stderr, "Recording:  earl-scribe-"
                assert_includes stderr, ".m4a"
              end
            end
          end
        end
      end

      test "run_local without --record omits recording line" do
        device = build_device
        whisper = build_mock_whisper(available: true, text: nil)
        mock_capture = build_mock_chunked_capture([])

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Transcription::Whisper.stub(:new, whisper) do
            EarlScribe::Audio::Capture.stub(:new, mock_capture) do
              EarlScribe::Speaker::Encoder.stub(:available?, false) do
                _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--local"]) }
                assert_not_includes stderr, "Recording:"
              end
            end
          end
        end
      end

      test "run_deepgram banner shows speaker ID enabled" do
        device = build_device
        client = build_mock_client
        capture = build_mock_capture

        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
            EarlScribe::Speaker::Encoder.stub(:available?, true) do
              EarlScribe::Speaker::SessionResolver.stub(:new, build_mock_resolver([])) do
                EarlScribe::Transcription::Deepgram.stub(:new, client) do
                  EarlScribe::Audio::Capture.stub(:new, capture) do
                    _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run([]) }
                    assert_includes stderr, "Speaker ID: enabled"
                  end
                end
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
        capture.define_singleton_method(:channels) { 2 }
        capture.define_singleton_method(:start_streaming) { |&_block| nil }
        capture
      end

      def build_mock_whisper(available:, text: nil)
        whisper = Object.new
        whisper.define_singleton_method(:available?) { available }
        whisper.define_singleton_method(:transcribe) { |_path| text }
        whisper
      end

      def build_mock_chunked_capture(wav_paths)
        capture = Object.new
        capture.define_singleton_method(:start_chunked) do |_dir, chunk_seconds: 10, &block|
          wav_paths.each { |path| block.call(path) }
        end
        capture
      end

      def build_mock_identifier(name)
        identifier = Object.new
        identifier.define_singleton_method(:identify) { |_embedding| [name, 0.9] }
        identifier
      end

      def build_mock_streaming_capture(data)
        capture = Object.new
        capture.define_singleton_method(:channels) { 2 }
        capture.define_singleton_method(:start_streaming) do |&block|
          block.call(data)
        end
        capture
      end

      def build_mock_resolver(buffer_data)
        pcm_buffer = Object.new
        pcm_buffer.define_singleton_method(:append) { |data| buffer_data << data }

        resolver = Object.new
        resolver.define_singleton_method(:pcm_buffer) { pcm_buffer }
        resolver.define_singleton_method(:resolve_label) { |speaker_id, _words| "Speaker #{speaker_id}" }
        resolver.define_singleton_method(:shutdown) { nil }
        resolver
      end
    end
  end
end
