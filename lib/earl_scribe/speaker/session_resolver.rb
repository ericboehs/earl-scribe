# frozen_string_literal: true

require "fileutils"
require "monitor"
require "tmpdir"

module EarlScribe
  module Speaker
    # Session-scoped async speaker identification coordinator.
    # Resolves Deepgram speaker IDs (0, 1, 2...) to enrolled speaker names
    # by extracting WAV segments from a PCM buffer and running voiceprint matching.
    class SessionResolver
      include MonitorMixin

      MIN_DURATION = 2.0
      SPEAKER_RE = /\A((?:Ch\d+ )?)(\d+)\z/.freeze

      attr_reader :pcm_buffer

      def self.build(channels:, identify:, sample_rate: 48_000, threshold: nil, &on_speaker_identified)
        return nil unless identify && Encoder.available?

        encoder = Encoder.start_server
        new(pcm_buffer: Audio::PcmBuffer.new(sample_rate: sample_rate, channels: channels),
            identifier: Identifier.new(store: Store.new, threshold: threshold),
            tmp_dir: Dir.mktmpdir("earl-scribe"), encoder: encoder, &on_speaker_identified)
      rescue StandardError
        encoder&.shutdown
        raise
      end

      def initialize(pcm_buffer:, identifier:, tmp_dir:, encoder: Encoder, &on_speaker_identified)
        super()
        @pcm_buffer = pcm_buffer
        @tmp_dir = tmp_dir
        @encoder = encoder
        @on_speaker_identified = on_speaker_identified
        @cache = {}
        @queue = Thread::Queue.new
        @worker = Thread.new { process_jobs(identifier, tmp_dir) }
      end

      def resolve_label(cache_key, words, channel: nil)
        synchronize do
          cached = @cache[cache_key]
          return cached if cached.is_a?(String)

          enqueue(cache_key, words, channel: channel) unless cached == :pending
          nil
        end
      end

      def shutdown
        @queue.close
        @worker.join(5)
        @encoder.shutdown if @encoder.is_a?(Encoder::PersistentProcess)
        cache = synchronize { @cache.select { |_, v| v.is_a?(String) } }
        FileUtils.rm_rf(@tmp_dir) if @tmp_dir
        cache
      end

      private

      def enqueue(cache_key, words, channel: nil)
        s = words.first&.dig("start")
        e = words.last&.dig("end")
        return unless s && e && e - s >= MIN_DURATION

        @cache[cache_key] = :pending
        @queue << { cache_key: cache_key, start_time: s, end_time: e, channel: channel }
      end

      def process_jobs(identifier, tmp_dir)
        while (job = @queue.pop)
          process_single_job(job, identifier, tmp_dir)
        end
      rescue ThreadError # rubocop:disable Lint/SuppressedException -- queue closed
      end

      def process_single_job(job, identifier, tmp_dir)
        cache_key = job[:cache_key]
        wav_path = @pcm_buffer.extract_wav(job[:start_time], job[:end_time],
                                           tmp_dir: tmp_dir, channel: job[:channel])
        return clear_pending(cache_key) unless wav_path

        identify_from_wav(cache_key, wav_path, identifier)
      rescue StandardError => error
        clear_pending(cache_key)
        EarlScribe.logger.warn("Speaker identification failed for #{cache_key}: #{error.message}")
      end

      def clear_pending(cache_key)
        synchronize { @cache.delete(cache_key) }
      end

      def identify_from_wav(cache_key, wav_path, identifier)
        name, _similarity = identifier.identify(@encoder.encode(wav_path))
        name ? apply_result(cache_key, name) : clear_pending(cache_key)
      ensure
        FileUtils.rm_f(wav_path)
      end

      def apply_result(cache_key, name)
        synchronize do
          @cache[cache_key] = name
          @on_speaker_identified&.call(cache_key, speaker_label(cache_key), name)
        end
      end

      def speaker_label(cache_key)
        return "Speaker 0" if cache_key.start_with?("wk-")

        (m = cache_key.match(SPEAKER_RE)) ? "#{m[1]}Speaker #{m[2]}" : cache_key
      end
    end
  end
end
