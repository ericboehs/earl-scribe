# frozen_string_literal: true

module EarlScribe
  module Cli
    # Lists available audio input devices via ffmpeg/avfoundation
    module Devices
      def self.run(_argv)
        devices = Audio::Device.list

        if devices.empty?
          warn "No audio devices found. Is ffmpeg installed?"
        else
          print_devices(devices)
        end
      end

      def self.print_devices(devices)
        puts "Audio input devices:"
        puts ""
        devices.each { |dev| puts "  [#{dev.index}] #{dev.name}" }
      end

      private_class_method :print_devices
    end
  end
end
