# frozen_string_literal: true

module EarlScribe
  module Cli
    # Starts a live transcription session via Deepgram or local whisper.cpp
    module Transcribe
      FLAG_MAP = {
        "--local" => [:local, true],
        "--mono" => [:mono, true],
        "--no-identify" => [:identify, false]
      }.freeze

      def self.run(argv)
        options = parse_options(argv)
        device = Audio::Device.resolve(options[:device])

        options[:local] ? run_local : run_deepgram(device, options)
      end

      def self.parse_options(argv)
        options = default_options(argv)
        argv.each { |flag| apply_flag(options, flag) }
        options
      end

      def self.default_options(argv)
        device_index = argv.index("--device")
        device = device_index ? argv[device_index + 1] : Config.audio_device
        { device: device, local: false, mono: false, identify: true }
      end

      def self.apply_flag(options, flag)
        mapping = FLAG_MAP[flag]
        options[mapping[0]] = mapping[1] if mapping
      end

      def self.run_deepgram(device, options)
        api_key = Config.deepgram_api_key
        abort "DEEPGRAM_API_KEY not set. Get a key at: https://console.deepgram.com/signup" unless api_key

        print_banner(device, options)
        start_stream(api_key, device, options[:mono] ? 1 : 2)
      end

      def self.start_stream(api_key, device, channels)
        client = build_client(api_key, channels)
        Audio::Capture.new(device_index: device.index, channels: channels)
                      .start_streaming { |data| client.send_audio(data) }
      rescue Interrupt
        client.close
      end

      def self.build_client(api_key, channels)
        client = Transcription::Deepgram.new(api_key: api_key, channels: channels)
        client.connect(method(:handle_result))
        client
      end

      def self.handle_result(result)
        Transcription::WordGrouper.group(result[:words]).each { |seg| puts seg }
      end

      def self.run_local
        whisper = Transcription::Whisper.new
        abort "whisper.cpp not available. Set WHISPER_CPP_PATH and WHISPER_MODELS_DIR." unless whisper.available?

        warn "Local whisper.cpp transcription is not yet fully implemented."
        warn "Use 'earl-scribe transcribe' (without --local) for Deepgram streaming."
      end

      def self.print_banner(device, options)
        mode = options[:mono] ? "mono + diarize" : "stereo (L=Meeting, R=Mic) + diarize"
        warn "=== Meeting Transcription (Deepgram Nova-3) ===\nDevice: [#{device.index}] #{device.name}\n" \
             "Mode:   #{mode}\n\nRecording... Press Ctrl+C to stop.\n---\n"
      end

      private_class_method :parse_options, :default_options, :apply_flag,
                           :run_deepgram, :start_stream, :build_client,
                           :handle_result, :run_local, :print_banner
    end
  end
end
