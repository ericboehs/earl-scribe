# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Cli
    class TranscribeTest < Minitest::Test
      setup do
        @data_dir = Dir.mktmpdir("transcribe_test")
      end

      teardown do
        FileUtils.rm_rf(@data_dir)
      end

      test "run warns on unknown flags" do
        with_local_stub do
          _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--bogus"]) }
          assert_includes stderr, "unknown flag"
          assert_includes stderr, "--bogus"
        end
      end

      test "run does not warn on value flag arguments" do
        with_local_stub do
          _stdout, stderr = capture_io do
            EarlScribe::Cli::Transcribe.run(["--title", "Daily", "--mic", "TestMic"])
          end
          assert_not_includes stderr, "unknown flag"
        end
      end

      test "run with --cloud aborts without api key" do
        device = build_device
        EarlScribe::Audio::Device.stub(:resolve, device) do
          EarlScribe::Config.stub(:deepgram_api_key, nil) do
            error = assert_raises(SystemExit) do
              EarlScribe::Cli::Transcribe.run(["--cloud", "--device", "TestMic"])
            end
            assert_equal 1, error.status
          end
        end
      end

      test "run defaults to LocalStream" do
        client = build_mock_client
        capture = build_mock_capture(channels: 1)
        captured_class = nil

        client.define_singleton_method(:connect) { |_cb| captured_class = :local }
        with_test_env(local_stub: client, dual_capture_stub: capture) do
          capture_io { EarlScribe::Cli::Transcribe.run([]) }
        end
        assert_equal :local, captured_class
      end

      test "default banner labels the local engine" do
        with_test_env(local_stub: build_mock_client, dual_capture_stub: build_mock_capture(channels: 1)) do
          _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run([]) }
          assert_includes stderr, "Parakeet"
          assert_includes stderr, "system + mic mono mix"
        end
      end

      test "default with --stereo warns and forces mono" do
        captured_channels = nil
        dual_stub = lambda { |**kwargs|
          captured_channels = kwargs[:channels]
          build_mock_capture(channels: 1)
        }
        with_test_env(local_stub: build_mock_client, dual_capture_stub: dual_stub) do
          _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--stereo"]) }
          assert_includes stderr, "stereo is ignored"
        end
        assert_equal 1, captured_channels
      end

      test "default with --no-mic uses AudioTee" do
        client = build_mock_client
        capture = build_mock_capture(channels: 1)
        with_test_env(local_stub: ->(**_) { client }, audiotee_stub: capture) do
          _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--no-mic"]) }
          assert_includes stderr, "System Audio (audiotee)"
        end
      end

      test "--native skips capture, uses LocalStream wait_until_done" do
        captured_kwargs = nil
        waited = false
        client = build_mock_client
        client.define_singleton_method(:wait_until_done) { waited = true }
        local_stub = lambda { |**kwargs|
          captured_kwargs = kwargs
          client
        }
        with_test_env(local_stub: local_stub) do
          _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--native"]) }
          assert_includes stderr, "native ScreenCaptureKit"
        end
        assert waited
        assert_equal({ mic: true, wav_path: nil }, captured_kwargs[:native])
      end

      test "--native --no-mic propagates mic: false" do
        captured = nil
        client = build_mock_client
        client.define_singleton_method(:wait_until_done) { nil }
        local_stub = lambda { |**kwargs|
          captured = kwargs
          client
        }
        with_test_env(local_stub: local_stub) do
          capture_io { EarlScribe::Cli::Transcribe.run(["--native", "--no-mic"]) }
        end
        assert_equal({ mic: false, wav_path: nil }, captured[:native])
      end

      test "--native interrupt is swallowed and teardown runs" do
        client = build_mock_client
        client.define_singleton_method(:wait_until_done) { raise Interrupt }
        closed = false
        client.define_singleton_method(:close) { closed = true }
        with_test_env(local_stub: ->(**_) { client }) do
          capture_io { EarlScribe::Cli::Transcribe.run(["--native"]) }
        end
        assert closed
      end

      test "default with --device passes device name" do
        device = build_device
        resolved = nil
        resolver = lambda { |name|
          resolved = name
          device
        }
        EarlScribe::Audio::Device.stub(:resolve, resolver) do
          with_test_env(local_stub: build_mock_client, capture_stub: build_mock_capture(channels: 1)) do
            capture_io { EarlScribe::Cli::Transcribe.run(["--device", "Meeting"]) }
          end
        end
        assert_equal "Meeting", resolved
      end

      test "local stream tees audio to PcmBuffer when resolver enabled" do
        buffered = []
        resolver = build_mock_resolver(buffered)
        client = build_mock_client
        capture = build_mock_streaming_capture("audio-bytes", channels: 1)

        with_test_env(local_stub: client, dual_capture_stub: capture, resolver: resolver) do
          capture_io { EarlScribe::Cli::Transcribe.run([]) }
        end

        assert_equal ["audio-bytes"], buffered
      end

      test "local stream without resolver still forwards audio" do
        sent = []
        client = build_mock_client
        client.define_singleton_method(:send_audio) { |data| sent << data }
        capture = build_mock_streaming_capture("bytes-no-resolver", channels: 1)

        with_test_env(local_stub: client, dual_capture_stub: capture) do
          capture_io { EarlScribe::Cli::Transcribe.run([]) }
        end
        assert_equal ["bytes-no-resolver"], sent
      end

      test "local stream interrupt with resolver shuts down resolver" do
        resolver = build_mock_resolver([])
        called = false
        resolver.define_singleton_method(:shutdown) do
          called = true
          {}
        end
        client = build_mock_client
        capture = build_interrupting_capture(channels: 1)

        with_test_env(local_stub: client, dual_capture_stub: capture, resolver: resolver) do
          capture_io { EarlScribe::Cli::Transcribe.run([]) }
        end
        assert called, "resolver.shutdown was not invoked"
      end

      test "handle_result with channels > 1 prefixes speaker labels" do
        client = build_mock_client
        client.define_singleton_method(:connect) do |callback|
          callback.call(channel_index: 1,
                        words: [{ "speaker" => 0, "punctuated_word" => "hi",
                                  "word" => "hi", "start" => 0.0, "end" => 1.0 }])
        end
        capture = build_mock_capture(channels: 2)
        captured = []

        EarlScribe::Cli::TerminalDisplay.stub(:new, fake_term_display(captured)) do
          EarlScribe::Config.stub(:deepgram_api_key, "k") do
            EarlScribe::Speaker::Encoder.stub(:available?, false) do
              EarlScribe::Transcription::Deepgram.stub(:new, client) do
                EarlScribe::Audio::DualCapture.stub(:new, capture) do
                  EarlScribe.stub(:data_dir, @data_dir) do
                    capture_io { EarlScribe::Cli::Transcribe.run(["--cloud", "--stereo"]) }
                  end
                end
              end
            end
          end
        end
        assert_match(/Ch1 Speaker 0/, captured.first.speaker)
      end

      test "resolve_speaker keeps original speaker when resolver returns nil" do
        resolver = build_mock_resolver([])
        resolver.define_singleton_method(:resolve_label) { |_ck, _w, **_o| nil }
        client = build_mock_client
        client.define_singleton_method(:connect) do |callback|
          callback.call(channel_index: 0,
                        words: [{ "speaker" => 0, "punctuated_word" => "hi",
                                  "word" => "hi", "start" => 0.0, "end" => 1.0 }])
        end
        capture = build_mock_capture(channels: 1)
        captured = []

        EarlScribe::Cli::TerminalDisplay.stub(:new, fake_term_display(captured)) do
          with_test_env(local_stub: client, dual_capture_stub: capture, resolver: resolver) do
            capture_io { EarlScribe::Cli::Transcribe.run([]) }
          end
        end
        assert_equal "Speaker 0", captured.first.speaker
        assert_nil captured.first.original_speaker
      end

      test "write_segment commits each segment as its own line" do
        client = build_mock_client
        client.define_singleton_method(:connect) do |callback|
          callback.call(channel_index: 0,
                        words: [{ "speaker" => 0, "punctuated_word" => "hi",
                                  "word" => "hi", "start" => 0.0, "end" => 1.0 }])
        end
        capture = build_mock_capture(channels: 1)
        captured = []
        EarlScribe::Cli::TerminalDisplay.stub(:new, fake_term_display(captured)) do
          with_test_env(local_stub: client, dual_capture_stub: capture) do
            capture_io { EarlScribe::Cli::Transcribe.run([]) }
          end
        end
        assert_equal 1, captured.size
      end

      test "correct_files maps Speaker-prefixed keys through SPEAKER_RE" do
        rewrites = []
        EarlScribe::Cli::LearnRewriter.stub(:rewrite, ->(paths, map) { rewrites << [paths, map] }) do
          run_cloud_interrupt(speaker_map: { "Speaker 1" => "Bob" })
        end
        _, map = rewrites.first
        assert_equal({ "Speaker 1" => "Bob" }, map)
      end

      test "--cloud interrupt without resolver still cleans up" do
        client = build_mock_client
        capture = build_interrupting_capture(channels: 2)

        EarlScribe::Config.stub(:deepgram_api_key, "k") do
          EarlScribe::Speaker::Encoder.stub(:available?, false) do
            EarlScribe::Transcription::Deepgram.stub(:new, client) do
              EarlScribe::Audio::DualCapture.stub(:new, capture) do
                EarlScribe.stub(:data_dir, @data_dir) do
                  capture_io { EarlScribe::Cli::Transcribe.run(["--cloud"]) }
                end
              end
            end
          end
        end
      end

      test "handle_result renames speaker when resolver returns a match" do
        resolver = build_mock_resolver([])
        resolver.define_singleton_method(:resolve_label) { |_ck, _w, **_o| "Alice" }
        client = build_mock_client
        client.define_singleton_method(:connect) do |callback|
          callback.call(channel_index: 0,
                        words: [{ "speaker" => 0, "punctuated_word" => "hi",
                                  "word" => "hi", "start" => 0.0, "end" => 1.0 }])
        end
        capture = build_mock_capture(channels: 1)

        captured_segments = []
        EarlScribe::Cli::TerminalDisplay.stub(:new, fake_term_display(captured_segments)) do
          with_test_env(local_stub: client, dual_capture_stub: capture, resolver: resolver) do
            capture_io { EarlScribe::Cli::Transcribe.run([]) }
          end
        end
        assert_equal "Alice", captured_segments.first.speaker
        assert_equal "Speaker 0", captured_segments.first.original_speaker
      end

      test "default --no-identify skips resolver creation" do
        captured_identify = nil
        resolver_builder = lambda { |**kwargs, &_blk|
          captured_identify = kwargs[:identify]
          nil
        }
        with_test_env(local_stub: build_mock_client,
                      dual_capture_stub: build_mock_capture(channels: 1),
                      resolver_builder: resolver_builder) do
          capture_io { EarlScribe::Cli::Transcribe.run(["--no-identify"]) }
        end
        assert_equal false, captured_identify
      end

      test "interrupt during local stream cleans up writers" do
        client = build_mock_client
        capture = build_interrupting_capture(channels: 1)

        with_test_env(local_stub: ->(**_) { client }, dual_capture_stub: capture) do
          capture_io { EarlScribe::Cli::Transcribe.run([]) }
        end
      end

      test "--cloud routes through Deepgram" do
        client = build_mock_client
        capture = build_mock_capture(channels: 2)

        EarlScribe::Config.stub(:deepgram_api_key, "test-key") do
          EarlScribe::Speaker::Encoder.stub(:available?, false) do
            EarlScribe::Transcription::Deepgram.stub(:new, ->(**_) { client }) do
              EarlScribe::Audio::DualCapture.stub(:new, ->(**_) { capture }) do
                EarlScribe.stub(:data_dir, @data_dir) do
                  _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--cloud"]) }
                  assert_includes stderr, "Deepgram Nova-3"
                end
              end
            end
          end
        end
      end

      test "--cloud with --stereo interleaves dual capture" do
        client = build_mock_client
        captured_channels = nil
        dual_stub = lambda { |**kwargs|
          captured_channels = kwargs[:channels]
          build_mock_capture(channels: 2)
        }
        EarlScribe::Config.stub(:deepgram_api_key, "key") do
          EarlScribe::Speaker::Encoder.stub(:available?, false) do
            EarlScribe::Transcription::Deepgram.stub(:new, ->(**_) { client }) do
              EarlScribe::Audio::DualCapture.stub(:new, dual_stub) do
                EarlScribe.stub(:data_dir, @data_dir) do
                  capture_io { EarlScribe::Cli::Transcribe.run(["--cloud", "--stereo"]) }
                end
              end
            end
          end
        end
        assert_equal 2, captured_channels
      end

      test "--cloud interrupt passes resolver speaker map through to rewriter" do
        rewrites = []
        EarlScribe::Cli::LearnRewriter.stub(:rewrite, ->(paths, map) { rewrites << [paths, map] }) do
          run_cloud_interrupt(speaker_map: { "seg-0.000" => "Alice" })
        end
        assert_equal 1, rewrites.size
        _, map = rewrites.first
        assert_equal({ "seg-0.000" => "Alice" }, map)
      end

      test "--cloud interrupt with empty speaker map skips file correction" do
        rewrites = []
        EarlScribe::Cli::LearnRewriter.stub(:rewrite, ->(*args) { rewrites << args }) do
          run_cloud_interrupt(speaker_map: {})
        end
        assert_empty rewrites
      end

      test "default banner shows transcript path and meeting title" do
        title = "Sprint Planning"
        EarlScribe::Calendar.stub(:current_meeting, { title: title }) do
          with_test_env(local_stub: build_mock_client, dual_capture_stub: build_mock_capture(channels: 1)) do
            _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run([]) }
            assert_includes stderr, title
            assert_includes stderr, "Transcript:"
          end
        end
      end

      test "scheduler starts and writes summary path when Qwen available" do
        client = build_mock_client
        capture = build_mock_capture(channels: 1)
        summarizer = Object.new
        summarizer.define_singleton_method(:available?) { true }

        scheduler = Object.new
        starts = 0
        stops = 0
        scheduler.define_singleton_method(:start) { starts += 1 }
        scheduler.define_singleton_method(:stop) { stops += 1 }

        captured_output_path = nil
        EarlScribe::Summarizer::Qwen.stub(:new, summarizer) do
          EarlScribe::Summarizer::Scheduler.stub(:new, lambda { |**kw|
            captured_output_path = kw[:output_path]
            scheduler
          }) do
            with_test_env(local_stub: client, dual_capture_stub: capture) do
              capture_io { EarlScribe::Cli::Transcribe.run(["--summary"]) }
            end
          end
        end
        assert_equal 1, starts
        assert_equal 1, stops
        assert captured_output_path.end_with?("-summary.md")
      end

      test "scheduler not built by default (summary off)" do
        client = build_mock_client
        capture = build_mock_capture(channels: 1)
        called = false
        EarlScribe::Summarizer::Qwen.stub(:new, lambda { |*|
          called = true
          nil
        }) do
          with_test_env(local_stub: client, dual_capture_stub: capture) do
            capture_io { EarlScribe::Cli::Transcribe.run([]) }
          end
        end
        assert_not called
      end

      test "scheduler not built when Qwen unavailable" do
        client = build_mock_client
        capture = build_mock_capture(channels: 1)
        unavailable = Object.new
        unavailable.define_singleton_method(:available?) { false }
        unavailable.define_singleton_method(:unavailable_reason) { "model missing" }
        sched_calls = 0
        EarlScribe::Summarizer::Qwen.stub(:new, unavailable) do
          EarlScribe::Summarizer::Scheduler.stub(:new, ->(**_) { sched_calls += 1 }) do
            with_test_env(local_stub: client, dual_capture_stub: capture) do
              capture_io { EarlScribe::Cli::Transcribe.run(["--summary"]) }
            end
          end
        end
        assert_equal 0, sched_calls
      end

      test "transcript_source returns nil when transcript file is missing" do
        ctx_struct = Struct.new(:paths)
        ctx = ctx_struct.new({ transcript: "/no/such/path", recording: nil, jsonl: nil })
        sum = Object.new
        sum.define_singleton_method(:available?) { true }

        captured_source = nil
        EarlScribe::Summarizer::Qwen.stub(:new, sum) do
          EarlScribe::Summarizer::Scheduler.stub(:new, lambda { |**kw|
            captured_source = kw[:transcript_source]
            nil
          }) do
            EarlScribe::Cli::Transcribe.send(:build_summary_scheduler, ctx,
                                             summarize: true, summary_interval_sec: 60)
          end
        end
        assert_nil captured_source.call
      end

      test "default --record shows recording path in banner" do
        with_test_env(local_stub: build_mock_client, dual_capture_stub: build_mock_capture(channels: 1)) do
          _stdout, stderr = capture_io { EarlScribe::Cli::Transcribe.run(["--record"]) }
          assert_includes stderr, "Recording:"
        end
      end

      test "default writes jsonl sidecar with metadata" do
        client = build_mock_client
        capture = build_mock_capture(channels: 1)

        with_test_env(local_stub: client, dual_capture_stub: capture) do
          capture_io { EarlScribe::Cli::Transcribe.run(["--title", "Standup"]) }
        end
        path = Dir.glob(File.join(@data_dir, "*.jsonl")).first
        assert path, "expected jsonl file under #{@data_dir}"
        first = JSON.parse(File.read(path).each_line.first)
        assert_equal "Standup", first["meeting_title"]
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
        client.define_singleton_method(:on_partial) { |&_blk| nil }
        client
      end

      def build_mock_capture(channels: 1)
        capture = Object.new
        capture.define_singleton_method(:channels) { channels }
        capture.define_singleton_method(:sample_rate) { 48_000 }
        capture.define_singleton_method(:start_streaming) { |&_block| nil }
        capture
      end

      def build_mock_streaming_capture(data, channels: 1)
        capture = Object.new
        capture.define_singleton_method(:channels) { channels }
        capture.define_singleton_method(:sample_rate) { 48_000 }
        capture.define_singleton_method(:start_streaming) { |&block| block.call(data) }
        capture
      end

      def build_interrupting_capture(channels: 1)
        capture = Object.new
        capture.define_singleton_method(:channels) { channels }
        capture.define_singleton_method(:sample_rate) { 48_000 }
        capture.define_singleton_method(:start_streaming) { |&_block| raise Interrupt }
        capture
      end

      def fake_term_display(captured)
        display = Object.new
        display.define_singleton_method(:commit) do |seg, **_kwargs|
          captured << seg
          nil
        end
        display.define_singleton_method(:reprint_speaker) { |*_args| nil }
        display
      end

      def build_mock_resolver(buffer_data)
        pcm_buffer = Object.new
        pcm_buffer.define_singleton_method(:append) { |data| buffer_data << data }

        resolver = Object.new
        resolver.define_singleton_method(:pcm_buffer) { pcm_buffer }
        resolver.define_singleton_method(:resolve_label) { |_cache_key, _words, **_opts| nil }
        resolver.define_singleton_method(:shutdown) { {} }
        resolver
      end

      def with_local_stub(&block)
        client = build_mock_client
        capture = build_mock_capture(channels: 1)
        with_test_env(local_stub: client, dual_capture_stub: capture, &block)
      end

      def with_test_env(local_stub: nil, dual_capture_stub: nil, audiotee_stub: nil,
                        capture_stub: nil, resolver: nil, resolver_builder: nil, &block)
        builder = resolver_builder || resolver
        EarlScribe::Speaker::Encoder.stub(:available?, !(resolver.nil? && resolver_builder.nil?)) do
          EarlScribe::Speaker::SessionResolver.stub(:build, builder) do
            EarlScribe::Transcription::LocalStream.stub(:new, local_stub) do
              EarlScribe::Audio::DualCapture.stub(:new, dual_capture_stub) do
                EarlScribe::Audio::AudioTee.stub(:new, audiotee_stub) do
                  EarlScribe::Audio::Capture.stub(:new, capture_stub) do
                    EarlScribe.stub(:data_dir, @data_dir, &block)
                  end
                end
              end
            end
          end
        end
      end

      def run_cloud_interrupt(speaker_map:)
        client = build_mock_client
        capture = build_interrupting_capture(channels: 2)
        resolver = build_mock_resolver([])
        resolver.define_singleton_method(:shutdown) { speaker_map }

        EarlScribe::Config.stub(:deepgram_api_key, "key") do
          EarlScribe::Speaker::Encoder.stub(:available?, true) do
            EarlScribe::Speaker::SessionResolver.stub(:build, resolver) do
              EarlScribe::Transcription::Deepgram.stub(:new, ->(**_) { client }) do
                EarlScribe::Audio::DualCapture.stub(:new, ->(**_) { capture }) do
                  EarlScribe.stub(:data_dir, @data_dir) do
                    capture_io { EarlScribe::Cli::Transcribe.run(["--cloud"]) }
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
