# frozen_string_literal: true

module EarlScribe
  module Cli
    # CLI flag parsing for the `transcribe` command.
    module TranscribeFlags
      FLAG_MAP = { "--local" => [:local, true], "--stereo" => [:stereo, true],
                   "--no-identify" => [:identify, false], "--record" => [:record, true],
                   "--no-mic" => [:no_mic, true] }.freeze
      VALUE_FLAGS = %w[--device --mic --threshold --title].freeze

      def self.parse(argv)
        warn_unknown_flags(argv)
        val = ->(flag) { (i = argv.index(flag)) && argv[i + 1] }
        opts = default_options(val)
        argv.each { |flag| (kv = FLAG_MAP[flag]) && (opts[kv[0]] = kv[1]) }
        opts
      end

      def self.default_options(val)
        { device: val["--device"] || (Config.audio_device_explicit? ? Config.audio_device : nil),
          mic: val["--mic"] || Config.audio_mic,
          threshold: val["--threshold"]&.to_f, title: val["--title"],
          local: false, stereo: false, identify: true, record: false, no_mic: false }
      end

      def self.warn_unknown_flags(argv)
        unknown = unknown_flags(argv)
        warn "warning: unknown flag(s): #{unknown.join(", ")}" if unknown.any?
      end

      def self.unknown_flags(argv)
        value_positions = argv.each_index.select { |i| VALUE_FLAGS.include?(argv[i]) }.map { |i| i + 1 }
        argv.each_with_index.filter_map do |arg, i|
          next if value_positions.include?(i)

          arg if unknown?(arg)
        end
      end

      def self.unknown?(arg)
        arg.start_with?("--") && !VALUE_FLAGS.include?(arg) && !FLAG_MAP.key?(arg)
      end

      private_class_method :default_options, :warn_unknown_flags, :unknown_flags, :unknown?
    end
  end
end
