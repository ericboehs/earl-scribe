# frozen_string_literal: true

module EarlScribe
  module Cli
    # Computes channel count, banner labels, and capture-mode descriptors from
    # parsed CLI options.
    module TranscribeMode
      def self.channels(opts)
        opts[:stereo] ? 2 : 1
      end

      def self.device_mode?(opts)
        !(opts[:device].nil? || opts[:device].empty?)
      end

      def self.resolve_device_name(opts)
        opts[:device] || Config.audio_device
      end

      def self.describe(device, opts, channels)
        return device_label(channels) if device
        return native_label(opts) if opts[:native]
        return "system audio (mono)" if opts[:no_mic]

        channels == 1 ? "system + mic mono mix" : "stereo (L=System, R=Mic) interleaved"
      end

      def self.device_label_for_banner(device, opts)
        return "[#{device.index}] #{device.name}" if device
        return native_device_label(opts) if opts[:native]
        return "System Audio (audiotee)" if opts[:no_mic]

        "System Audio (audiotee) + Mic (#{opts[:mic]})"
      end

      def self.native_label(opts)
        opts[:no_mic] ? "system audio (ScreenCaptureKit)" : "system + mic mono mix (ScreenCaptureKit)"
      end

      def self.native_device_label(opts)
        opts[:no_mic] ? "ScreenCaptureKit" : "ScreenCaptureKit + AVAudioEngine mic"
      end

      private_class_method :native_label, :native_device_label

      def self.device_label(channels)
        channels == 1 ? "mono + diarize" : "stereo (L=Meeting, R=Mic) + diarize"
      end

      private_class_method :device_label
    end
  end
end
