# frozen_string_literal: true

require "fileutils"
require "monitor"

module EarlScribe
  module Speaker
    # Session-scoped async speaker identification coordinator.
    # Resolves Deepgram speaker IDs (0, 1, 2...) to enrolled speaker names
    # by extracting WAV segments from a PCM buffer and running voiceprint matching.
    class SessionResolver
      include MonitorMixin

      MIN_DURATION = 2.0 # seconds of audio needed for identification

      attr_reader :pcm_buffer

      def initialize(pcm_buffer:, identifier:, tmp_dir:)
        super()
        @pcm_buffer = pcm_buffer
        @tmp_dir = tmp_dir
        @cache = {}
        @queue = Thread::Queue.new
        @worker = Thread.new { process_jobs(identifier, tmp_dir) }
      end

      def resolve_label(speaker_id, words)
        synchronize do
          cached = @cache[speaker_id]
          return cached if cached.is_a?(String)

          queue_identification(speaker_id, words) unless cached == :pending
          "Speaker #{speaker_id}"
        end
      end

      def shutdown
        @queue.close
        @worker.join(5)
        FileUtils.rm_rf(@tmp_dir) if @tmp_dir
      end

      private

      def queue_identification(speaker_id, words)
        start_time = words.first&.dig("start")
        end_time = words.last&.dig("end")
        return unless start_time && end_time
        return if end_time - start_time < MIN_DURATION

        @cache[speaker_id] = :pending
        @queue << { speaker_id: speaker_id, start_time: start_time, end_time: end_time }
      end

      def process_jobs(identifier, tmp_dir)
        while (job = next_job)
          process_single_job(job, identifier, tmp_dir)
        end
      end

      def next_job
        @queue.pop
      rescue ThreadError
        nil
      end

      def process_single_job(job, identifier, tmp_dir)
        speaker_id = job[:speaker_id]
        wav_path = @pcm_buffer.extract_wav(job[:start_time], job[:end_time], tmp_dir: tmp_dir)
        unless wav_path
          synchronize { @cache.delete(speaker_id) }
          return
        end

        identify_from_wav(speaker_id, wav_path, identifier)
      rescue StandardError => error
        synchronize { @cache.delete(speaker_id) }
        EarlScribe.logger.warn("Speaker identification failed for speaker #{speaker_id}: #{error.message}")
      end

      def identify_from_wav(speaker_id, wav_path, identifier)
        embedding = Encoder.encode(wav_path)
        name, _similarity = identifier.identify(embedding)
        synchronize { @cache[speaker_id] = name } if name
      ensure
        FileUtils.rm_f(wav_path)
      end
    end
  end
end
