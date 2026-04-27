# frozen_string_literal: true

require_relative "transcribe_banner"
require_relative "transcribe_flags"
require_relative "transcribe_mode"
require_relative "transcribe_session"
require_relative "transcribe_summarizer"
require_relative "terminal_display"
require_relative "learn_rewriter"

module EarlScribe
  module Cli
    module Transcribe
      SPEAKER_RE = /\A((?:Ch\d+ )?)Speaker (\d+)\z/.freeze

      def self.run(argv)
        opts = TranscribeFlags.parse(argv)
        device = resolve_device(opts)
        opts[:cloud] ? run_cloud(device, opts) : run_local(device, opts)
      end

      def self.resolve_device(opts)
        return nil unless TranscribeMode.device_mode?(opts)

        Audio::Device.resolve(TranscribeMode.resolve_device_name(opts))
      end

      def self.run_local(device, opts)
        warn_stereo_local(opts)
        opts = opts.merge(stereo: false)
        ctx = build_context(device, opts, channels: 1)
        resolver = build_resolver(ctx, opts)
        scheduler = build_summary_scheduler(ctx, opts)
        announce(ctx, device, opts, 1, resolver, "Parakeet EOU 120M (local)")
        scheduler&.start
        stream_local(ctx, resolver, opts)
      ensure
        scheduler&.stop
      end

      def self.run_cloud(device, opts)
        api_key = Config.deepgram_api_key || abort("DEEPGRAM_API_KEY not set. Get a key at: https://console.deepgram.com/signup")
        channels = TranscribeMode.channels(opts)
        ctx = build_context(device, opts, channels: channels)
        resolver = build_resolver(ctx, opts)
        announce(ctx, device, opts, channels, resolver, "Deepgram Nova-3")
        stream_cloud(api_key, ctx, resolver)
      end

      def self.build_context(device, opts, channels:)
        ctx = TranscribeSession.build(device, opts, channels: channels)
        ctx.term_display = TerminalDisplay.new
        ctx
      end

      def self.warn_stereo_local(opts)
        return unless opts[:stereo]

        warn "warning: --stereo is ignored with the local backend (mono mix is required)"
      end

      def self.announce(ctx, device, opts, channels, resolver, engine)
        title = opts[:title] || ctx.meeting&.dig(:title)
        TranscribeBanner.print(engine: engine, mode: TranscribeMode.describe(device, opts, channels),
                               device_label: TranscribeMode.device_label_for_banner(device, opts),
                               id_status: resolver ? "enabled" : "disabled",
                               session: TranscribeSession.session_info(ctx, meeting_title: title))
      end

      def self.build_summary_scheduler(ctx, opts)
        TranscribeSummarizer.build(ctx, opts)
      end

      def self.build_resolver(ctx, opts)
        capture = ctx.capture
        Speaker::SessionResolver.build(
          channels: capture.channels, sample_rate: capture.sample_rate,
          identify: opts[:identify], threshold: opts[:threshold]
        ) { |ck, old_n, new_n| ctx.term_display.reprint_speaker(ck, old_n, new_n) }
      end

      def self.stream_local(ctx, resolver, _opts)
        client = nil
        begin
          capture = ctx.capture
          client = Transcription::LocalStream.new(channels: capture.channels,
                                                  sample_rate: capture.sample_rate)
          client.connect(->(result) { handle_result(result, resolver, ctx) })
          capture.start_streaming { |data| forward_chunk(client, resolver, data) }
        rescue Interrupt
          nil
        end
      ensure
        teardown_local(ctx, client, resolver)
      end

      def self.teardown_local(ctx, client, resolver)
        safe_step { client&.close }
        safe_step { correct_files(ctx, resolver&.shutdown) }
        safe_step { TranscribeSession.close_writers(ctx) }
      end

      def self.safe_step
        yield
      rescue StandardError => error
        EarlScribe.logger.error("teardown step failed: #{error.class}: #{error.message}")
      end

      def self.stream_cloud(api_key, ctx, resolver)
        client = nil
        begin
          capture = ctx.capture
          client = Transcription::Deepgram.new(api_key: api_key, channels: capture.channels,
                                               sample_rate: capture.sample_rate)
          client.connect(->(result) { handle_result(result, resolver, ctx) })
          capture.start_streaming { |data| forward_chunk(client, resolver, data) }
        rescue Interrupt
          nil
        end
      ensure
        teardown_local(ctx, client, resolver)
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
        seg.cache_key = cache_key
        ctx.term_display.commit(seg, cache_key: cache_key)
        ctx.writer.write_line(seg.to_timestamped_s)
        ctx.jsonl.write_segment(seg)
      end

      def self.resolve_speaker(seg, words, resolver)
        return unless (match = resolver && seg.speaker&.match(SPEAKER_RE))

        cache_key = segment_cache_key(seg, match)
        name = resolver.resolve_label(cache_key, words, channel: seg.channel, speaker_label: seg.speaker)
        if name
          seg.original_speaker = seg.speaker
          seg.speaker = name
        end
        cache_key
      end

      def self.segment_cache_key(seg, match)
        prefix = match[1]
        ts = format("%.3f", seg.start_time.to_f)
        "#{prefix}seg-#{ts}"
      end

      def self.correct_files(ctx, map)
        return unless map&.any?

        LearnRewriter.rewrite({ jsonl_path: ctx.paths[:jsonl] }, map)
      end

      private_class_method(*%i[resolve_device run_local run_cloud build_context warn_stereo_local
                               announce build_resolver build_summary_scheduler
                               stream_local stream_cloud teardown_local safe_step
                               forward_chunk handle_result
                               write_segment resolve_speaker segment_cache_key correct_files])
    end
  end
end
