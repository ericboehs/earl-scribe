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

      test "resolve_label returns Speaker N for unknown speakers" do
        resolver = build_resolver
        words = build_words(start_time: 0.0, end_time: 3.0)

        label = resolver.resolve_label(0, words)
        assert_equal "Speaker 0", label
        resolver.shutdown
      end

      test "resolve_label returns cached name after identification" do
        # Pre-fill the buffer with enough audio
        @pcm_buffer.append("\x01" * 128_000) # 4 seconds

        resolver = build_resolver_with_stubs(identified_name: "Alice")
        words = build_words(start_time: 0.0, end_time: 3.0)

        # First call queues identification
        label = resolver.resolve_label(0, words)
        assert_equal "Speaker 0", label

        # Give worker thread time to process
        sleep 0.2

        # Second call should return cached name
        label = resolver.resolve_label(0, words)
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
        resolver.resolve_label(0, words)
        resolver.resolve_label(0, words)

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

      test "handles encoder failure gracefully" do
        @pcm_buffer.append("\x01" * 128_000)
        resolver = build_resolver

        Encoder.stub(:encode, ->(_p) { raise EarlScribe::Error, "encoder broke" }) do
          words = build_words(start_time: 0.0, end_time: 3.0)
          label = resolver.resolve_label(0, words)
          assert_equal "Speaker 0", label
          sleep 0.2
        end

        # Should still work after failure
        label = resolver.resolve_label(0, build_words(start_time: 0.0, end_time: 3.0))
        assert_equal "Speaker 0", label
        resolver.shutdown
      end

      test "handles nil from extract_wav when audio trimmed" do
        resolver = build_resolver
        words = build_words(start_time: 0.0, end_time: 3.0)

        # Buffer is empty, so extract_wav returns nil
        label = resolver.resolve_label(0, words)
        assert_equal "Speaker 0", label
        sleep 0.2

        resolver.shutdown
      end

      test "skips words with insufficient duration" do
        @pcm_buffer.append("\x01" * 32_000) # 1 second

        resolver = build_resolver
        words = build_words(start_time: 0.0, end_time: 1.0) # < 2 second minimum

        label = resolver.resolve_label(0, words)
        assert_equal "Speaker 0", label
        resolver.shutdown
      end

      test "skips words without timestamps" do
        resolver = build_resolver
        words = [{ "word" => "hello", "speaker" => 0 }]

        label = resolver.resolve_label(0, words)
        assert_equal "Speaker 0", label
        resolver.shutdown
      end

      test "skips empty words array" do
        resolver = build_resolver
        label = resolver.resolve_label(0, [])

        assert_equal "Speaker 0", label
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

      test "returns Speaker N when identifier finds no match" do
        @pcm_buffer.append("\x01" * 128_000)

        mock_identifier = Object.new
        mock_identifier.define_singleton_method(:identify) { |_emb| [nil, 0.3] }

        resolver = SessionResolver.new(pcm_buffer: @pcm_buffer, identifier: mock_identifier, tmp_dir: @tmp_dir)
        stub_singleton(Encoder, :encode) { |_path| [0.1, 0.2, 0.3] }

        words = build_words(start_time: 0.0, end_time: 3.0)
        resolver.resolve_label(0, words)
        sleep 0.2

        label = resolver.resolve_label(0, words)
        assert_equal "Speaker 0", label
        resolver.shutdown
      end

      private

      def build_resolver
        SessionResolver.new(pcm_buffer: @pcm_buffer, identifier: @identifier, tmp_dir: @tmp_dir)
      end

      def build_resolver_with_stubs(identified_name:)
        mock_identifier = Object.new
        mock_identifier.define_singleton_method(:identify) { |_emb| [identified_name, 0.9] }

        resolver = SessionResolver.new(pcm_buffer: @pcm_buffer, identifier: mock_identifier, tmp_dir: @tmp_dir)

        # Stub Encoder.encode to return a fake embedding
        stub_singleton(Encoder, :encode) { |_path| [0.1, 0.2, 0.3] }

        resolver
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
