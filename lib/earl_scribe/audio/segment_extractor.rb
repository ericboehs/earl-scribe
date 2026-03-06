# frozen_string_literal: true

require "open3"

module EarlScribe
  module Audio
    # Extracts WAV clips from M4A recordings for speaker enrollment
    module SegmentExtractor
      MIN_DURATION = 2.0

      def self.extract_wav(m4a_path, start_time, end_time, output_path:)
        duration = end_time - start_time
        _stdout, stderr, status = Open3.capture3(
          "ffmpeg", "-y", "-i", m4a_path,
          "-ss", start_time.to_s, "-t", duration.to_s,
          "-ar", "16000", "-ac", "1", "-f", "wav", output_path
        )
        raise Error, "ffmpeg extraction failed: #{stderr}" unless status.success?

        output_path
      end

      def self.extract_best_segments(m4a_path, segments, tmp_dir:, count: 3)
        candidates = segments.select { |seg| seg.duration >= MIN_DURATION }
                             .sort_by { |seg| -seg.duration }
                             .first(count)

        candidates.map.with_index do |seg, idx|
          wav_path = File.join(tmp_dir, "segment_#{idx}.wav")
          extract_wav(m4a_path, seg.start_time, seg.end_time, output_path: wav_path)
          { segment: seg, wav_path: wav_path }
        end
      end
    end
  end
end
