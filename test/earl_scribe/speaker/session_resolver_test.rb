# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module EarlScribe
  module Speaker
    class SessionResolverTest < Minitest::Test
      setup do
        @tmp_dir = Dir.mktmpdir("resolver_test")
        @pcm_buffer = Audio::PcmBuffer.new(sample_rate: 16_000, channels: 1)
        @identifier = Identifier.new(store: Store.new(speakers_dir: @tmp_dir))
      end

      teardown do
        FileUtils.rm_rf(@tmp_dir)
      end

      test "resolve_label returns nil for unknown speakers" do
        resolver = build_resolver
        words = build_words(start_time: 0.0, end_time: 3.0)

        label = resolver.resolve_label("0", words)
        assert_nil label
        resolver.shutdown
      end

      test "resolve_label returns cached name after identification" do
        @pcm_buffer.append("\x01" * 128_000)

        resolver = build_resolver_with_stubs(identified_name: "Alice")
        words = build_words(start_time: 0.0, end_time: 3.0)

        label = resolver.resolve_label("0", words)
        assert_nil label

        sleep 0.2

        label = resolver.resolve_label("0", words)
        assert_equal "Alice", label
        resolver.shutdown
      end

      test "callback fires on initial identification" do
        @pcm_buffer.append("\x01" * 128_000)

        callbacks = []
        resolver = build_resolver_with_stubs(identified_name: "Alice") do |cache_key, old_name, new_name|
          callbacks << [cache_key, old_name, new_name]
        end

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        sleep 0.3

        assert_equal 1, callbacks.size
        assert_equal ["0", "Speaker 0", "Alice"], callbacks.first
        resolver.shutdown
      end

      test "callback fires on correction when name changes" do
        @pcm_buffer.append("\x01" * 128_000)

        call_count = 0
        callbacks = []
        mock_identifier = Object.new
        mock_identifier.define_singleton_method(:identify) do |_emb|
          call_count += 1
          name = call_count == 1 ? "Alice" : "Bob"
          [name, 0.9]
        end

        resolver = SessionResolver.new(
          pcm_buffer: @pcm_buffer, identifier: mock_identifier, tmp_dir: @tmp_dir,
          encoder: build_mock_encoder
        ) { |ck, old_n, new_n| callbacks << [ck, old_n, new_n] }

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        sleep 0.3

        # Should have initial callback
        assert_equal 1, callbacks.size

        # Second call returns "Alice" optimistically and queues verification
        label = resolver.resolve_label("0", words)
        assert_equal "Alice", label
        sleep 0.3

        # Verification found "Bob", should fire correction callback
        assert_equal 2, callbacks.size
        assert_equal %w[0 Alice Bob], callbacks.last
        resolver.shutdown
      end

      test "no callback when verification confirms same name" do
        @pcm_buffer.append("\x01" * 128_000)

        callbacks = []
        resolver = build_resolver_with_stubs(identified_name: "Alice") do |ck, old_n, new_n|
          callbacks << [ck, old_n, new_n]
        end

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        sleep 0.3

        assert_equal 1, callbacks.size # initial identification

        # Verification with same name should not fire callback
        resolver.resolve_label("0", words)
        sleep 0.3

        assert_equal 1, callbacks.size
        resolver.shutdown
      end

      test "optimistic cache returns name immediately on second call" do
        @pcm_buffer.append("\x01" * 128_000)

        resolver = build_resolver_with_stubs(identified_name: "Alice")
        words = build_words(start_time: 0.0, end_time: 3.0)

        resolver.resolve_label("0", words)
        sleep 0.2

        label = resolver.resolve_label("0", words)
        assert_equal "Alice", label
        resolver.shutdown
      end

      test "resolve_label does not re-queue pending speakers" do
        @pcm_buffer.append("\x01" * 128_000)

        queue_count = 0
        resolver = build_resolver
        original_queue = resolver.instance_variable_get(:@queue)

        counting_queue = Object.new
        counting_queue.define_singleton_method(:<<) do |job|
          queue_count += 1
          original_queue << job
        end
        counting_queue.define_singleton_method(:close) { original_queue.close }
        counting_queue.define_singleton_method(:pop) { original_queue.pop }
        resolver.instance_variable_set(:@queue, counting_queue)

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        resolver.resolve_label("0", words)

        assert_equal 1, queue_count
        resolver.shutdown
      end

      test "shutdown terminates worker thread" do
        resolver = build_resolver
        worker = resolver.instance_variable_get(:@worker)
        assert worker.alive?

        resolver.shutdown
        assert_not worker.alive?
      end

      test "shutdown returns speaker cache" do
        @pcm_buffer.append("\x01" * 128_000)

        resolver = build_resolver_with_stubs(identified_name: "Alice")
        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        sleep 0.2

        cache = resolver.shutdown
        assert_equal({ "0" => "Alice" }, cache)
      end

      test "shutdown shuts down PersistentProcess encoder" do
        shutdown_called = false
        mock_encoder = build_mock_encoder
        mock_encoder.define_singleton_method(:shutdown) { shutdown_called = true }
        mock_encoder.define_singleton_method(:is_a?) { |klass| klass == Encoder::PersistentProcess }

        resolver = SessionResolver.new(
          pcm_buffer: @pcm_buffer, identifier: @identifier, tmp_dir: @tmp_dir,
          encoder: mock_encoder
        )
        resolver.shutdown
        assert shutdown_called
      end

      test "handles encoder failure gracefully" do
        @pcm_buffer.append("\x01" * 128_000)
        resolver = build_resolver

        Encoder.stub(:encode, ->(_p) { raise EarlScribe::Error, "encoder broke" }) do
          words = build_words(start_time: 0.0, end_time: 3.0)
          label = resolver.resolve_label("0", words)
          assert_nil label
          sleep 0.2
        end

        # Should still work after failure (cache cleared, queues again)
        label = resolver.resolve_label("0", build_words(start_time: 0.0, end_time: 3.0))
        assert_nil label
        resolver.shutdown
      end

      test "handles nil from extract_wav when audio trimmed" do
        resolver = build_resolver
        words = build_words(start_time: 0.0, end_time: 3.0)

        # Buffer is empty, so extract_wav returns nil
        label = resolver.resolve_label("0", words)
        assert_nil label
        sleep 0.2

        resolver.shutdown
      end

      test "skips words with insufficient duration" do
        @pcm_buffer.append("\x01" * 32_000) # 1 second

        resolver = build_resolver
        words = build_words(start_time: 0.0, end_time: 1.0) # < 2 second minimum

        label = resolver.resolve_label("0", words)
        assert_nil label
        resolver.shutdown
      end

      test "skips words without timestamps" do
        resolver = build_resolver
        words = [{ "word" => "hello", "speaker" => 0 }]

        label = resolver.resolve_label("0", words)
        assert_nil label
        resolver.shutdown
      end

      test "skips empty words array" do
        resolver = build_resolver
        label = resolver.resolve_label("0", [])

        assert_nil label
        resolver.shutdown
      end

      test "build returns nil when identify is false" do
        assert_nil SessionResolver.build(channels: 2, identify: false)
      end

      test "build returns nil when encoder unavailable" do
        Encoder.stub(:available?, false) do
          assert_nil SessionResolver.build(channels: 2, identify: true)
        end
      end

      test "build returns resolver when identify true and encoder available" do
        Encoder.stub(:available?, true) do
          resolver = SessionResolver.build(channels: 2, identify: true)
          assert_instance_of SessionResolver, resolver
          resolver.shutdown
        end
      end

      test "returns nil when identifier finds no match" do
        @pcm_buffer.append("\x01" * 128_000)

        mock_identifier = Object.new
        mock_identifier.define_singleton_method(:identify) { |_emb| [nil, 0.3] }

        resolver = SessionResolver.new(
          pcm_buffer: @pcm_buffer, identifier: mock_identifier, tmp_dir: @tmp_dir,
          encoder: build_mock_encoder
        )

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        sleep 0.2

        label = resolver.resolve_label("0", words)
        assert_nil label
        resolver.shutdown
      end

      test "verification skips when words have insufficient duration" do
        @pcm_buffer.append("\x01" * 128_000)

        callbacks = []
        resolver = build_resolver_with_stubs(identified_name: "Alice") do |ck, old_n, new_n|
          callbacks << [ck, old_n, new_n]
        end

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        sleep 0.2

        # Second call with short words should return cached name but skip verification
        short_words = build_words(start_time: 0.0, end_time: 1.0)
        label = resolver.resolve_label("0", short_words)
        assert_equal "Alice", label
        sleep 0.1

        # Only the initial callback, no verification
        assert_equal 1, callbacks.size
        resolver.shutdown
      end

      test "verification skips when words have no timestamps" do
        @pcm_buffer.append("\x01" * 128_000)

        resolver = build_resolver_with_stubs(identified_name: "Alice")
        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        sleep 0.2

        label = resolver.resolve_label("0", [{ "word" => "hello", "speaker" => 0 }])
        assert_equal "Alice", label
        resolver.shutdown
      end

      test "clear_pending does not delete cache for verify jobs" do
        @pcm_buffer.append("\x01" * 128_000)

        resolver = build_resolver_with_stubs(identified_name: "Alice")
        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)
        sleep 0.2

        # Now empty the buffer so extract_wav returns nil for verify
        @pcm_buffer.instance_variable_set(:@buffer, "")
        resolver.resolve_label("0", words)
        sleep 0.2

        # Name should still be cached
        label = resolver.resolve_label("0", words)
        assert_equal "Alice", label
        resolver.shutdown
      end

      test "build rescue handles nil encoder before start_server returns" do
        Encoder.stub(:available?, true) do
          Encoder.stub(:start_server, -> { raise StandardError, "import error" }) do
            assert_raises(StandardError) { SessionResolver.build(channels: 1, identify: true) }
          end
        end
      end

      test "build rescue cleans up encoder on failure" do
        shutdown_called = false
        mock_server = Object.new
        mock_server.define_singleton_method(:shutdown) { shutdown_called = true }

        Encoder.stub(:available?, true) do
          Encoder.stub(:start_server, mock_server) do
            # Force Identifier.new to fail
            Identifier.stub(:new, ->(*_a) { raise StandardError, "boom" }) do
              assert_raises(StandardError) { SessionResolver.build(channels: 1, identify: true) }
            end
          end
        end

        assert shutdown_called
      end

      test "shutdown without PersistentProcess encoder does not call shutdown on encoder" do
        resolver = build_resolver
        cache = resolver.shutdown
        assert_equal({}, cache)
      end

      test "shutdown returns empty hash when only pending in cache" do
        @pcm_buffer.append("\x01" * 128_000)
        resolver = build_resolver
        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("0", words)

        cache = resolver.shutdown
        assert_equal({}, cache)
      end

      test "speaker_label returns key unchanged for non-matching pattern" do
        @pcm_buffer.append("\x01" * 128_000)

        callbacks = []
        mock_identifier = Object.new
        mock_identifier.define_singleton_method(:identify) { |_emb| ["Alice", 0.9] }

        resolver = SessionResolver.new(
          pcm_buffer: @pcm_buffer, identifier: mock_identifier, tmp_dir: @tmp_dir,
          encoder: build_mock_encoder
        ) { |ck, old_n, new_n| callbacks << [ck, old_n, new_n] }

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("custom_key", words)
        sleep 0.3

        assert_equal 1, callbacks.size
        assert_equal %w[custom_key custom_key Alice], callbacks.first
        resolver.shutdown
      end

      test "callback fires with channel-prefixed speaker label" do
        @pcm_buffer.append("\x01" * 128_000)

        callbacks = []
        mock_identifier = Object.new
        mock_identifier.define_singleton_method(:identify) { |_emb| ["Alice", 0.9] }

        resolver = SessionResolver.new(
          pcm_buffer: @pcm_buffer, identifier: mock_identifier, tmp_dir: @tmp_dir,
          encoder: build_mock_encoder
        ) { |ck, old_n, new_n| callbacks << [ck, old_n, new_n] }

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label("Ch0 0", words)
        sleep 0.3

        assert_equal 1, callbacks.size
        assert_equal ["Ch0 0", "Ch0 Speaker 0", "Alice"], callbacks.first
        resolver.shutdown
      end

      private

      def build_resolver
        SessionResolver.new(pcm_buffer: @pcm_buffer, identifier: @identifier, tmp_dir: @tmp_dir)
      end

      def build_resolver_with_stubs(identified_name:, &callback)
        mock_identifier = Object.new
        mock_identifier.define_singleton_method(:identify) { |_emb| [identified_name, 0.9] }

        SessionResolver.new(
          pcm_buffer: @pcm_buffer, identifier: mock_identifier, tmp_dir: @tmp_dir,
          encoder: build_mock_encoder, &callback
        )
      end

      def build_mock_encoder
        encoder = Module.new
        encoder.define_singleton_method(:encode) { |_path| [0.1, 0.2, 0.3] }
        encoder
      end

      def build_words(start_time:, end_time:)
        [
          { "word" => "hello", "punctuated_word" => "Hello", "speaker" => 0, "start" => start_time,
            "end" => start_time + 0.5 },
          { "word" => "world", "punctuated_word" => "world.", "speaker" => 0, "start" => end_time - 0.5,
            "end" => end_time }
        ]
      end
    end
  end
end
