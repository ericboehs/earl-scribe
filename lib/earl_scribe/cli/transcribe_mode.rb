# frozen_string_literal: true

module EarlScribe
  module Cli
    # Derives banner labels and channel counts from the options hash — one place
    # for the device/no-mic/dual-capture branching logic.
    module TranscribeMode
      def self.channels(opts)
        opts[:stereo] ? 2 : 1
      end

      def self.device_mode?(opts)
        opts[:local] || !(opts[:device].nil? || opts[:device].empty?)
      end

      def self.resolve_device_name(opts)
        opts[:device] || Config.audio_device
      end

      def self.describe(device, opts, channels)
        return device_label(channels) if device
        return "system audio (mono)" if opts[:no_mic]

        channels == 1 ? "system + mic mono mix" : "stereo (L=System, R=Mic) interleaved"
      end

      def self.device_label_for_banner(device, opts)
        return "[#{device.index}] #{device.name}" if device
        return "System Audio (audiotee)" if opts[:no_mic]

        "System Audio (audiotee) + Mic (#{opts[:mic]})"
      end

      def self.device_label(channels)
        channels == 1 ? "mono + diarize" : "stereo (L=Meeting, R=Mic) + diarize"
      end

      private_class_method :device_label
    end
  end
end
