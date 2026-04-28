# frozen_string_literal: true

module EarlScribe
  module Cli
    # Builds Transcription::LocalStream clients from CLI opts. Centralized so the
    # transcribe entrypoint stays focused on orchestration.
    module LocalStreamFactory
      def self.from_capture(capture, opts)
        Transcription::LocalStream.new(channels: capture.channels, sample_rate: capture.sample_rate,
                                       diarize: opts[:diarize] != false, diar: diar_opts(opts))
      end

      def self.native(opts, wav_path: nil)
        Transcription::LocalStream.new(channels: 1, sample_rate: 16_000,
                                       diarize: opts[:diarize] != false, diar: diar_opts(opts),
                                       native: { mic: !opts[:no_mic], wav_path: wav_path })
      end

      def self.diar_opts(opts)
        { debug: opts[:diar_debug] == true, variant: opts[:diar_variant],
          wait_ms: opts[:diar_wait_ms] }
      end
      private_class_method :diar_opts
    end
  end
end
