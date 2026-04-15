# frozen_string_literal: true

require_relative "transcribe_banner"
require_relative "transcribe_flags"
require_relative "transcribe_mode"
require_relative "transcribe_session"
require_relative "transcribe_local"
require_relative "terminal_display"
require_relative "learn_rewriter"

module EarlScribe
  module Cli
    # Starts a live transcription session via Deepgram or local whisper.cpp
    module Transcribe
      SPEAKER_RE = /\A((?:Ch\d+ )?)Speaker (\d+)\z/.freeze

      def self.run(argv)
        opts = TranscribeFlags.parse(argv)
        device = resolve_device(opts)
        opts[:local] ? TranscribeLocal.run(device, opts) : run_deepgram(device, opts)
      end

      def self.resolve_device(opts)
        return nil unless TranscribeMode.device_mode?(opts)

        Audio::Device.resolve(TranscribeMode.resolve_device_name(opts))
      end

      def self.run_deepgram(device, opts)
        api_key = Config.deepgram_api_key || abort("DEEPGRAM_API_KEY not set. Get a key at: https://console.deepgram.com/signup")
        channels = TranscribeMode.channels(opts)
        ctx = TranscribeSession.build(device, opts, channels: channels)
        ctx.term_display = TerminalDisplay.new
        resolver = build_resolver(ctx, opts)
        print_banner(ctx, device, opts, channels, resolver)
        stream_deepgram(api_key, ctx, resolver)
      end

      def self.print_banner(ctx, device, opts, channels, resolver)
        title = opts[:title] || ctx.meeting&.dig(:title)
        TranscribeBanner.print(engine: "Deepgram Nova-3", mode: TranscribeMode.describe(device, opts, channels),
                               device_label: TranscribeMode.device_label_for_banner(device, opts),
                               id_status: resolver ? "enabled" : "disabled",
                               session: TranscribeSession.session_info(ctx, meeting_title: title))
      end

      def self.build_resolver(ctx, opts)
        capture = ctx.capture
        Speaker::SessionResolver.build(
          channels: capture.channels, sample_rate: capture.sample_rate,
          identify: opts[:identify], threshold: opts[:threshold]
        ) { |ck, old_n, new_n| ctx.term_display.reprint_speaker(ck, old_n, new_n) }
      end

      def self.stream_deepgram(api_key, ctx, resolver)
        capture = ctx.capture
        client = Transcription::Deepgram.new(api_key: api_key, channels: capture.channels,
                                             sample_rate: capture.sample_rate)
        client.connect(->(result) { handle_result(result, resolver, ctx) })
        capture.start_streaming { |data| forward_chunk(client, resolver, data) }
      rescue Interrupt
        client.close
        correct_files(ctx, resolver&.shutdown)
        TranscribeSession.close_writers(ctx)
      end

      def self.forward_chunk(client, resolver, data)
        client.send_audio(data)
        resolver&.pcm_buffer&.append(data)
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
        ctx.writer.write_line(flushed.to_timestamped_s) if flushed
        ctx.jsonl.write_segment(seg)
      end

      def self.resolve_speaker(seg, words, resolver)
        return unless (match = resolver && seg.speaker&.match(SPEAKER_RE))

        cache_key = "#{match[1]}#{match[2]}"
        if (name = resolver.resolve_label(cache_key, words, channel: seg.channel))
          seg.original_speaker = seg.speaker
          seg.speaker = name
        end
        cache_key
      end

      def self.correct_files(ctx, map)
        return unless map&.any?

        LearnRewriter.rewrite({ jsonl_path: ctx.paths[:jsonl] },
                              map.transform_keys { |k| (m = k.match(SPEAKER_RE)) ? "#{m[1]}Speaker #{m[2]}" : k })
      end

      private_class_method(*%i[resolve_device run_deepgram print_banner build_resolver
                               stream_deepgram forward_chunk handle_result write_segment
                               resolve_speaker correct_files])
    end
  end
end
