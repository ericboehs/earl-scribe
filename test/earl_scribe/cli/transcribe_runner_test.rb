# frozen_string_literal: true

require "test_helper"
require "earl_scribe/cli/transcribe_runner"

module EarlScribe
  module Cli
    class TranscribeRunnerTest < Minitest::Test
      Ctx = Struct.new(:capture, :paths, :term_display, :writer, :jsonl, :meeting, keyword_init: true)

      def test_safe_step_swallows_errors
        # Should not raise — TranscribeRunner.safe_step rescues and logs
        TranscribeRunner.safe_step { raise "boom" }
      end

      def test_forward_chunk_sends_audio_and_appends_to_buffer
        client_calls = []
        client = Object.new
        client.define_singleton_method(:send_audio) { |data| client_calls << data }
        buffer = Object.new
        appended = []
        buffer.define_singleton_method(:append) { |data| appended << data }
        resolver = Object.new
        resolver.define_singleton_method(:pcm_buffer) { buffer }

        TranscribeRunner.forward_chunk(client, resolver, "PCM")
        assert_equal ["PCM"], client_calls
        assert_equal ["PCM"], appended
      end

      def test_forward_chunk_no_op_resolver_buffer
        client_calls = []
        client = Object.new
        client.define_singleton_method(:send_audio) { |data| client_calls << data }
        # resolver = nil
        TranscribeRunner.forward_chunk(client, nil, "PCM")
        assert_equal ["PCM"], client_calls
      end

      def test_teardown_local_skips_correct_when_skip_correct_true
        client_closed = false
        client = Object.new
        client.define_singleton_method(:close) { client_closed = true }
        resolver = Object.new
        resolver.define_singleton_method(:shutdown) { { "0" => "Allison" } }

        ctx = Ctx.new(paths: { jsonl: "/dev/null" })
        TranscribeSession.stub(:close_writers, ->(_) {}) do
          # Should NOT call correct_files
          stubbed = []
          TranscribeSpeakerWriter.stub(:correct_files, ->(*) { stubbed << :called }) do
            TranscribeRunner.teardown_local(ctx, client, resolver, skip_correct: true)
            assert_empty stubbed
          end
        end
        assert client_closed
      end

      def test_teardown_local_calls_correct_when_skip_correct_false
        client = Object.new
        client.define_singleton_method(:close) {}
        resolver = Object.new
        resolver.define_singleton_method(:shutdown) { { "0" => "Allison" } }

        ctx = Ctx.new(paths: { jsonl: "/dev/null" })
        called = false
        TranscribeSession.stub(:close_writers, ->(_) {}) do
          TranscribeSpeakerWriter.stub(:correct_files, ->(*) { called = true }) do
            TranscribeRunner.teardown_local(ctx, client, resolver, skip_correct: false)
          end
        end
        assert called
      end

      def test_teardown_local_handles_nil_resolver
        ctx = Ctx.new(paths: { jsonl: "/dev/null" })
        # Should not raise even with nil resolver/client
        TranscribeSession.stub(:close_writers, ->(_) {}) do
          TranscribeSpeakerWriter.stub(:correct_files, ->(*) {}) do
            TranscribeRunner.teardown_local(ctx, nil, nil)
          end
        end
      end
    end
  end
end
