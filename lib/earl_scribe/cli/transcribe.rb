# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "transcribe_banner"

module EarlScribe
  module Cli
    # Starts a live transcription session via Deepgram or local whisper.cpp
    module Transcribe
      FLAG_MAP = { "--local" => [:local, true], "--mono" => [:mono, true],
                   "--no-identify" => [:identify, false], "--record" => [:record, true] }.freeze

      def self.run(argv)
        options = parse_options(argv)
        device = Audio::Device.resolve(options[:device])
        options[:local] ? run_local(device, options) : run_deepgram(device, options)
      end

      def self.parse_options(argv)
        default_options(argv).tap { |opts| apply_flags(opts, argv) }
      end

      def self.default_options(argv)
        device_index = argv.index("--device")
        device = device_index ? argv[device_index + 1] : Config.audio_device
        { device: device, local: false, mono: false, identify: true, record: false }
      end

      def self.apply_flags(options, argv)
        argv.each do |flag|
          key, val = FLAG_MAP[flag]
          options[key] = val if key
        end
      end

      def self.run_deepgram(device, options)
        api_key = Config.deepgram_api_key || abort("DEEPGRAM_API_KEY not set. Get a key at: https://console.deepgram.com/signup")
        channels = options[:mono] ? 1 : 2
        resolver = Speaker::SessionResolver.build(channels: channels, identify: options[:identify])
        transcript_path, recording = Transcription::TranscriptWriter.build_paths(record: options[:record])
        capture = Audio::Capture.new(device_index: device.index, channels: channels, recording_path: recording)
        TranscribeBanner.print(device, engine: "Deepgram Nova-3", id_status: resolver ? "enabled" : "disabled",
                                       mode: options[:mono] ? "mono + diarize" : "stereo (L=Meeting, R=Mic) + diarize",
                                       paths: { transcript: transcript_path, recording: recording })
        start_stream(api_key, capture, resolver, Transcription::TranscriptWriter.new(transcript_path))
      end

      def self.start_stream(api_key, capture, resolver, writer)
        client = Transcription::Deepgram.new(api_key: api_key, channels: capture.channels)
        client.connect(->(result) { handle_result(result, resolver, writer) })
        capture.start_streaming do |data|
          client.send_audio(data)
          resolver&.pcm_buffer&.append(data)
        end
      rescue Interrupt
        client.close
        resolver&.shutdown
        writer.close
      end

      def self.handle_result(result, resolver, writer)
        words = result[:words]
        Transcription::WordGrouper.group(words).each do |seg|
          resolve_speaker(seg, words, resolver)
          writer.write_line(seg.to_s)
        end
      end

      def self.resolve_speaker(segment, words, resolver)
        match = resolver && segment.speaker&.match(/Speaker (\d+)\z/)
        segment.speaker = resolver.resolve_label(match[1].to_i, words) if match
      end

      def self.run_local(device, options)
        whisper = Transcription::Whisper.new
        abort "whisper.cpp not available. Set WHISPER_CPP_PATH and WHISPER_MODELS_DIR." unless whisper.available?
        id_ok = options[:identify] && Speaker::Encoder.available?
        identifier = id_ok ? Speaker::Identifier.new(store: Speaker::Store.new) : nil
        transcript_path, recording = Transcription::TranscriptWriter.build_paths(record: options[:record])
        capture = Audio::Capture.new(device_index: device.index, channels: 1, recording_path: recording)
        TranscribeBanner.print(device, engine: "whisper.cpp", mode: "local", id_status: id_ok ? "enabled" : "disabled",
                                       paths: { transcript: transcript_path, recording: recording })
        run_chunked_pipeline(capture, whisper, identifier, Transcription::TranscriptWriter.new(transcript_path))
      end

      def self.run_chunked_pipeline(capture, whisper, identifier, writer)
        Dir.mktmpdir("earl-scribe") do |tmp_dir|
          capture.start_chunked(tmp_dir, chunk_seconds: Config.audio_chunk_seconds) do |wav_path|
            process_chunk(wav_path, whisper, identifier, writer)
          end
        end
      rescue Interrupt
        nil
      ensure
        writer.close
      end

      def self.process_chunk(wav_path, whisper, identifier, writer)
        text = whisper.transcribe(wav_path)
        return unless text

        label = identify_speaker(wav_path, identifier)
        writer.write_line(label ? "#{label}: #{text}" : text)
      ensure
        FileUtils.rm_f(wav_path)
      end

      def self.identify_speaker(wav_path, identifier)
        return unless identifier

        identifier.identify(Speaker::Encoder.encode(wav_path))&.first
      end

      private_class_method :parse_options, :default_options, :apply_flags, :run_deepgram,
                           :start_stream, :handle_result, :resolve_speaker,
                           :run_local, :run_chunked_pipeline, :process_chunk,
                           :identify_speaker
    end
  end
end
