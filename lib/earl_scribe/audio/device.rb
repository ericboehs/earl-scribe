# frozen_string_literal: true

require "open3"

module EarlScribe
  module Audio
    # Resolves audio device names to avfoundation indices via ffmpeg
    module Device
      # Audio device with avfoundation index and display name
      DeviceInfo = Struct.new(:index, :name, keyword_init: true)

      def self.list
        parse_devices(ffmpeg_device_output)
      end

      def self.resolve(name_or_index)
        return DeviceInfo.new(index: name_or_index.to_i, name: name_or_index) if name_or_index.to_s.match?(/\A\d+\z/)

        device = list.find { |dev| dev.name.downcase.include?(name_or_index.downcase) }
        raise Error, "Audio device '#{name_or_index}' not found. Run: earl-scribe devices" unless device

        device
      end

      def self.ffmpeg_device_output
        _stdout, stderr, _status = Open3.capture3(
          "ffmpeg", "-f", "avfoundation", "-list_devices", "true", "-i", ""
        )
        stderr
      end

      def self.parse_devices(output)
        audio_lines = output.each_line.drop_while { |line| !line.include?("AVFoundation audio") }.drop(1)

        audio_lines.each_with_object([]) do |line, devices|
          match = line.match(/\[(\d+)\]\s+(.+)/)
          devices << DeviceInfo.new(index: match[1].to_i, name: match[2].strip) if match
        end
      end

      private_class_method :ffmpeg_device_output, :parse_devices
    end
  end
end
