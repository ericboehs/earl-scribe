# frozen_string_literal: true

module EarlScribe
  module Transcription
    # Builds the ASR shim command line. Lifted out of LocalStream to keep the
    # client class focused on subprocess lifecycle.
    module LocalStreamCommand
      module_function

      def build(opts)
        return whisperkit(opts[:asr_bin]) if opts[:engine] == :whisperkit

        source = opts[:native] ? native_args(opts[:native]) : stdin_args(opts[:sample_rate])
        [opts[:asr_bin], "--chunk-ms", opts[:chunk_ms].to_s, *source, *diar_flags(opts[:diar] || {})]
      end

      def stdin_args(sample_rate)
        ["--stdin", "--stdin-format", stdin_format(sample_rate)]
      end

      def whisperkit(asr_bin)
        model = Config.whisperkit_model
        raise Error, "EARL_SCRIBE_WHISPERKIT_MODEL must be set" unless model

        [asr_bin, "--model-path", model]
      end

      def native_args(native)
        cmd = native[:mic] ? ["--capture"] : ["--capture", "--no-mic"]
        native[:wav_path] ? cmd + ["--capture-wav", native[:wav_path]] : cmd
      end

      def diar_flags(diar)
        flags = []
        flags << "--no-diarize" if diar[:enabled] == false
        flags << "--diar-debug" if diar[:debug] == true
        flags += ["--diar-variant", diar[:variant]] if diar[:variant]
        flags += ["--diar-wait-ms", diar[:wait_ms].to_s] if diar[:wait_ms]
        flags
      end

      def stdin_format(sample_rate)
        sample_rate == 16_000 ? "f32_16k_mono" : "s16_48k_mono"
      end
    end
  end
end
