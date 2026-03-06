# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "transcribe_banner"
require_relative "transcribe_session"
require_relative "terminal_display"
require_relative "learn_rewriter"

module EarlScribe
  module Cli
    # Starts a live transcription session via Deepgram or local whisper.cpp
    module Transcribe
      FLAG_MAP = { "--local" => [:local, true], "--mono" => [:mono, true],
                   "--no-identify" => [:identify, false], "--record" => [:record, true] }.freeze
      SPEAKER_RE = /\A((?:Ch\d+ )?)Speaker (\d+)\z/.freeze

      def self.run(argv)
        opts = parse_options(argv)
        send(opts[:local] ? :run_local : :run_deepgram, Audio::Device.resolve(opts[:device]), opts)
      end

      def self.parse_options(argv)
        val = ->(flag) { (i = argv.index(flag)) && argv[i + 1] }
        opts = { device: val["--device"] || Config.audio_device, threshold: val["--threshold"]&.to_f,
                 local: false, mono: false, identify: true, record: false }
        argv.each { |flag| (kv = FLAG_MAP[flag]) && (opts[kv[0]] = kv[1]) }
        opts
      end

      def self.run_deepgram(device, opts)
        api_key = Config.deepgram_api_key || abort("DEEPGRAM_API_KEY not set. Get a key at: https://console.deepgram.com/signup")
        ctx = TranscribeSession.build(device, opts, channels: opts[:mono] ? 1 : 2)
        ctx.term_display = TerminalDisplay.new
        resolver = build_resolver(ctx, opts)
        mode = opts[:mono] ? "mono + diarize" : "stereo (L=Meeting, R=Mic) + diarize"
        TranscribeBanner.print(device, engine: "Deepgram Nova-3", mode: mode,
                                       id_status: resolver ? "enabled" : "disabled",
                                       session: TranscribeSession.session_info(ctx))
        stream_deepgram(api_key, ctx, resolver)
      end

      def self.build_resolver(ctx, opts)
        Speaker::SessionResolver.build(
          channels: ctx.capture.channels, identify: opts[:identify], threshold: opts[:threshold]
        ) { |ck, old_n, new_n| ctx.term_display.reprint_speaker(ck, old_n, new_n) }
      end

      def self.stream_deepgram(api_key, ctx, resolver)
        client = Transcription::Deepgram.new(api_key: api_key, channels: ctx.capture.channels)
        client.connect(->(result) { handle_result(result, resolver, ctx) })
        ctx.capture.start_streaming do |data|
          client.send_audio(data)
          resolver&.pcm_buffer&.append(data)
        end
      rescue Interrupt
        client.close
        correct_files(ctx, resolver&.shutdown)
        TranscribeSession.close_writers(ctx)
      end

      def self.handle_result(result, resolver, ctx)
        prefix = ctx.capture.channels > 1 ? "Ch#{result[:channel_index]}" : nil
        Transcription::WordGrouper.group(result[:words], speaker_prefix: prefix).each do |seg|
          seg.channel = result[:channel_index]
          write_segment(ctx, seg, resolve_speaker(seg, result[:words], resolver))
        end
      end

      def self.write_segment(ctx, seg, cache_key)
        flushed = ctx.term_display.accumulate(seg, cache_key: cache_key)
        ctx.writer.write_line(flushed.to_s) if flushed
        ctx.jsonl.write_segment(seg)
      end

      def self.resolve_speaker(seg, words, resolver)
        return unless (match = resolver && seg.speaker&.match(SPEAKER_RE))

        cache_key = "#{match[1]}#{match[2]}"
        (name = resolver.resolve_label(cache_key, words, channel: seg.channel)) && (seg.speaker = name)
        cache_key
      end

      def self.correct_files(ctx, map)
        return unless map&.any?

        LearnRewriter.rewrite({ jsonl_path: ctx.paths[:jsonl] },
                              map.transform_keys { |k| (m = k.match(SPEAKER_RE)) ? "#{m[1]}Speaker #{m[2]}" : k })
      end

      def self.run_local(device, opts)
        whisper = Transcription::Whisper.new
        abort "whisper.cpp not available. Set WHISPER_CPP_PATH and WHISPER_MODELS_DIR." unless whisper.available?
        id_ok = opts[:identify] && Speaker::Encoder.available?
        ctx = TranscribeSession.build(device, opts)
        TranscribeBanner.print(device, engine: "whisper.cpp", mode: "local", id_status: id_ok ? "enabled" : "disabled",
                                       session: TranscribeSession.session_info(ctx))
        identifier = Speaker::Identifier.new(store: Speaker::Store.new, threshold: opts[:threshold]) if id_ok
        run_chunked(ctx, whisper, identifier)
      end

      def self.run_chunked(ctx, whisper, identifier)
        elapsed = 0.0
        Dir.mktmpdir("earl-scribe") do |tmp_dir|
          ctx.capture.start_chunked(tmp_dir, chunk_seconds: Config.audio_chunk_seconds) do |wav_path|
            elapsed = process_chunk(wav_path, whisper, identifier, ctx, elapsed)
          end
        end
      rescue Interrupt
        nil
      ensure
        TranscribeSession.close_writers(ctx)
      end

      def self.process_chunk(wav_path, whisper, identifier, ctx, elapsed)
        return elapsed unless (text = whisper.transcribe(wav_path))

        label = identifier&.identify(Speaker::Encoder.encode(wav_path))&.first
        seg = Transcription::Result.new(speaker: label, text: text, start_time: elapsed, channel: 0)
        puts seg.to_timestamped_s
        ctx.writer.write_line(seg.to_s)
        ctx.jsonl.write_segment(seg)
        elapsed + Config.audio_chunk_seconds
      ensure
        FileUtils.rm_f(wav_path)
      end

      private_class_method(*%i[parse_options run_deepgram build_resolver stream_deepgram handle_result
                               write_segment resolve_speaker correct_files run_local run_chunked process_chunk])
    end
  end
end
