# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "transcribe_banner"
require_relative "transcribe_session"

module EarlScribe
  module Cli
    # Local whisper.cpp transcription path — captures audio in chunked WAV files
    # and transcribes each chunk via whisper.cpp subprocess.
    module TranscribeLocal
      def self.run(device, opts)
        whisper = Transcription::Whisper.new
        abort "whisper.cpp not available. Set WHISPER_CPP_PATH and WHISPER_MODELS_DIR." unless whisper.available?
        id_ok = opts[:identify] && Speaker::Encoder.available?
        ctx = TranscribeSession.build(device, opts)
        title = opts[:title] || ctx.meeting&.dig(:title)
        TranscribeBanner.print(device, engine: "whisper.cpp", mode: "local", id_status: id_ok ? "enabled" : "disabled",
                                       session: TranscribeSession.session_info(ctx, meeting_title: title))
        identifier = Speaker::Identifier.new(store: Speaker::Store.new, threshold: opts[:threshold]) if id_ok
        run_chunked(ctx, whisper, identifier)
      end

      # Bundles the per-chunk dependencies (session context, whisper wrapper, and speaker identifier)
      ChunkContext = Struct.new(:ctx, :whisper, :identifier, keyword_init: true)

      def self.run_chunked(ctx, whisper, identifier)
        chunk_ctx = ChunkContext.new(ctx: ctx, whisper: whisper, identifier: identifier)
        Dir.mktmpdir("earl-scribe") { |tmp_dir| process_all_chunks(chunk_ctx, tmp_dir) }
      rescue Interrupt
        nil
      ensure
        TranscribeSession.close_writers(ctx)
      end

      def self.process_all_chunks(chunk_ctx, tmp_dir)
        elapsed = 0.0
        chunk_ctx.ctx.capture.start_chunked(tmp_dir, chunk_seconds: Config.audio_chunk_seconds) do |wav_path|
          elapsed = process_chunk(wav_path, chunk_ctx, elapsed)
        end
      end

      def self.process_chunk(wav_path, chunk_ctx, elapsed)
        return elapsed unless (text = chunk_ctx.whisper.transcribe(wav_path))

        seg = build_segment(wav_path, text, chunk_ctx.identifier, elapsed)
        emit_segment(chunk_ctx.ctx, seg)
        elapsed + Config.audio_chunk_seconds
      ensure
        FileUtils.rm_f(wav_path)
      end

      def self.build_segment(wav_path, text, identifier, elapsed)
        label = identifier&.identify(Speaker::Encoder.encode(wav_path))&.first
        Transcription::Result.new(speaker: label, text: text, start_time: elapsed, channel: 0)
      end

      def self.emit_segment(ctx, seg)
        timestamped = seg.to_timestamped_s
        puts timestamped
        ctx.writer.write_line(timestamped)
        ctx.jsonl.write_segment(seg)
      end

      private_class_method :run_chunked, :process_all_chunks, :process_chunk, :build_segment, :emit_segment
    end
  end
end
