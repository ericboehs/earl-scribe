# frozen_string_literal: true

require_relative "local_stream_factory"
require_relative "rerun"
require_relative "transcribe_session"
require_relative "transcribe_speaker_writer"

module EarlScribe
  module Cli
    # Streams audio through an ASR client (local or cloud) and routes parsed
    # results to the writers. Lifted out of Cli::Transcribe to keep that
    # orchestrator under the lint length budget.
    module TranscribeRunner
      module_function

      def stream_native(ctx, opts)
        wav = opts[:rerun] ? ctx.paths[:wav] : nil
        client = LocalStreamFactory.native(opts, wav_path: wav)
        run_local_client(ctx, nil, client, &:wait_until_done)
        Rerun.run(ctx.paths, opts) if opts[:rerun]
      end

      def stream_local(ctx, resolver, opts)
        client = LocalStreamFactory.from_capture(ctx.capture, opts)
        whisperkit = opts[:engine] == :whisperkit
        run_local_client(ctx, resolver, client, per_segment: whisperkit, skip_correct: whisperkit) do
          ctx.capture.start_streaming { |data| forward_chunk(client, resolver, data) }
        end
      end

      def stream_cloud(api_key, ctx, resolver)
        capture = ctx.capture
        client = Transcription::Deepgram.new(api_key: api_key, channels: capture.channels,
                                             sample_rate: capture.sample_rate)
        run_local_client(ctx, resolver, client) do
          capture.start_streaming { |data| forward_chunk(client, resolver, data) }
        end
      end

      def run_local_client(ctx, resolver, client, per_segment: false, skip_correct: false)
        client.connect(lambda { |result|
          TranscribeSpeakerWriter.handle_result(result, resolver, ctx, per_segment: per_segment)
        })
        yield client
      rescue Interrupt
        nil
      ensure
        teardown_local(ctx, client, resolver, skip_correct: skip_correct)
      end

      def teardown_local(ctx, client, resolver, skip_correct: false)
        safe_step { client&.close }
        cache = resolver&.shutdown
        safe_step { TranscribeSpeakerWriter.correct_files(ctx, cache) } unless skip_correct
        safe_step { TranscribeSession.close_writers(ctx) }
      end

      def forward_chunk(client, resolver, data)
        client.send_audio(data)
        resolver&.pcm_buffer&.append(data)
      end

      def safe_step
        yield
      rescue StandardError => error
        EarlScribe.logger.error("teardown step failed: #{error.class}: #{error.message}")
      end
    end
  end
end
