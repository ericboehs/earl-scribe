# frozen_string_literal: true

require "open3"
require "fileutils"

module EarlScribe
  module Cli
    # Audio-side helpers for the rerun: WAV normalization, m4a encoding, and
    # WAV duration parsing. Kept out of Cli::Rerun to keep that module focused
    # on orchestration.
    module RerunAudio
      module_function

      # Pad applied to the rerun's WAV before transcription. Without it,
      # Parakeet TDT batch mode consistently drops the first ~20s of audio.
      PAD_SEC = 1.0

      # ffmpeg-rewrite the captured WAV through a standard PCM container with
      # a 1s leading silence pad. The pad is trimmed from emitted timestamps
      # (see Cli::Rerun#event_to_segment) so live and rerun timelines stay
      # aligned.
      def normalize_wav(wav)
        return nil unless wav && File.exist?(wav)

        normalized = "#{wav}.norm.wav"
        _out, _err, status = Open3.capture3("ffmpeg", "-y", "-i", wav,
                                            "-af", "adelay=#{(PAD_SEC * 1000).to_i}|#{(PAD_SEC * 1000).to_i}",
                                            "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
                                            normalized)
        return normalized if status.success?

        FileUtils.rm_f(normalized)
        nil
      end

      def encode_m4a(wav, m4a)
        _out, err, status = Open3.capture3("ffmpeg", "-y", "-i", wav, "-c:a", "aac", "-b:a", "96k", m4a)
        return if status.success?

        warn "ffmpeg encode failed: #{err.lines.last(2).join.strip}"
      end

      # Read RIFF/data chunk sizes from the WAV header to compute audio length.
      # The shim writes 16k mono Int16 (2 B/sample), so duration = data_bytes / (16k*2).
      def wav_duration_sec(path)
        bytes = File.read(path, 44)
        return nil unless bytes && bytes.bytesize == 44

        data_bytes = bytes[40, 4].unpack1("V")
        data_bytes.to_f / (16_000 * 2)
      end
    end
  end
end
