# frozen_string_literal: true

module EarlScribe
  module Cli
    # Builds Transcription::LocalStream clients from CLI opts. Centralized so the
    # transcribe entrypoint stays focused on orchestration.
    module LocalStreamFactory
      def self.from_capture(capture, opts)
        Transcription::LocalStream.new(channels: capture.channels, sample_rate: capture.sample_rate,
                                       diar: diar_opts(opts), engine: engine(opts))
      end

      def self.native(opts, wav_path: nil)
        Transcription::LocalStream.new(channels: 1, sample_rate: 16_000,
                                       diar: diar_opts(opts), engine: engine(opts),
                                       native: { mic: !opts[:no_mic], wav_path: wav_path })
      end

      def self.engine(opts)
        opts[:engine] == :whisperkit ? :whisperkit : :fluidaudio
      end

      def self.diar_opts(opts)
        { enabled: opts[:diarize] != false, debug: opts[:diar_debug] == true,
          variant: opts[:diar_variant], wait_ms: opts[:diar_wait_ms] }
      end
      private_class_method :engine, :diar_opts
    end
  end
end
