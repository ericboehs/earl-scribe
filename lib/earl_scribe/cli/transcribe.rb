# frozen_string_literal: true

require_relative "local_stream_factory"
require_relative "rerun"
require_relative "transcribe_banner"
require_relative "transcribe_flags"
require_relative "transcribe_mode"
require_relative "transcribe_session"
require_relative "transcribe_summarizer"
require_relative "terminal_display"
require_relative "learn_rewriter"
require_relative "transcribe_runner"
require_relative "transcribe_speaker_writer"
require_relative "whisperkit_diarize"

module EarlScribe
  module Cli
    # Top-level orchestration for the `earl-scribe transcribe` command. Dispatches
    # between local (Parakeet/WhisperKit) and cloud (Deepgram) engines, manages
    # session lifecycle, and runs the post-session diarization pass.
    module Transcribe
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
        opts = normalize_local_opts(opts)
        ctx, resolver, scheduler = build_local_session(device, opts)
        scheduler&.start
        run_local_stream(ctx, resolver, opts)
        WhisperkitDiarize.run(ctx.paths, opts) if opts[:engine] == :whisperkit
      ensure
        scheduler&.stop
      end

      def self.build_local_session(device, opts)
        ctx = build_context(device, opts, channels: 1)
        resolver = local_resolver(ctx, opts)
        announce(AnnounceArgs.new(ctx: ctx, device: device, opts: opts,
                                  channels: 1, resolver: resolver, engine: engine_label(opts)))
        [ctx, resolver, build_summary_scheduler(ctx, opts)]
      end

      def self.run_local_stream(ctx, resolver, opts)
        opts[:native] ? TranscribeRunner.stream_native(ctx, opts) : TranscribeRunner.stream_local(ctx, resolver, opts)
      end

      def self.normalize_local_opts(opts)
        opts.merge(stereo: false, record: opts[:record] || opts[:engine] == :whisperkit)
      end

      def self.local_resolver(ctx, opts)
        return nil if opts[:native]

        build_resolver(ctx, opts)
      end

      ENGINE_LABELS = {
        whisperkit: "WhisperKit large-v3 (local)",
        native: "Parakeet EOU 120M (native ScreenCaptureKit)",
        local: "Parakeet EOU 120M (local)"
      }.freeze

      def self.engine_label(opts)
        ENGINE_LABELS.fetch(engine_label_key(opts))
      end

      def self.engine_label_key(opts)
        return :whisperkit if opts[:engine] == :whisperkit

        opts[:native] ? :native : :local
      end

      def self.run_cloud(device, opts)
        api_key = Config.deepgram_api_key || abort("DEEPGRAM_API_KEY not set. Get a key at: https://console.deepgram.com/signup")
        channels = TranscribeMode.channels(opts)
        ctx = build_context(device, opts, channels: channels)
        resolver = build_resolver(ctx, opts)
        announce(AnnounceArgs.new(ctx: ctx, device: device, opts: opts,
                                  channels: channels, resolver: resolver, engine: "Deepgram Nova-3"))
        TranscribeRunner.stream_cloud(api_key, ctx, resolver)
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

      AnnounceArgs = Struct.new(:ctx, :device, :opts, :channels, :resolver, :engine,
                                keyword_init: true)

      def self.announce(args)
        TranscribeBanner.print(engine: args.engine,
                               mode: TranscribeMode.describe(args.device, args.opts, args.channels),
                               device_label: TranscribeMode.device_label_for_banner(args.device, args.opts),
                               id_status: args.resolver ? "enabled" : "disabled",
                               session: announce_session(args))
      end

      def self.announce_session(args)
        title = args.opts[:title] || args.ctx.meeting&.dig(:title)
        TranscribeSession.session_info(args.ctx, meeting_title: title)
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

      private_class_method(*%i[resolve_device run_local run_cloud build_context warn_stereo_local
                               announce announce_session build_resolver build_summary_scheduler
                               build_local_session run_local_stream
                               engine_label engine_label_key normalize_local_opts local_resolver])
    end
  end
end
