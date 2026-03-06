# frozen_string_literal: true

require "open3"
require "json"
require "mutex_m"
require "securerandom"

module EarlScribe
  module Speaker
    # Generates speaker embeddings by shelling out to a Python resemblyzer helper
    module Encoder
      HELPER_PATH = File.expand_path("../support/speaker_encoder.py", __dir__)
      SERVER_PATH = File.expand_path("../support/speaker_encoder_server.py", __dir__)

      def self.encode(wav_path)
        raise Error, "Audio file not found: #{wav_path}" unless File.exist?(wav_path)

        stdout, stderr, status = Open3.capture3("python3", HELPER_PATH, wav_path)
        raise Error, "Speaker encoder failed: #{stderr.strip}" unless status.success?

        JSON.parse(stdout)
      end

      def self.available?
        _stdout, _stderr, status = Open3.capture3("python3", "-c", "import resemblyzer")
        status.success?
      rescue Errno::ENOENT
        false
      end

      def self.start_server
        PersistentProcess.new
      end

      # Persistent Python encoder process that loads VoiceEncoder once
      class PersistentProcess
        include Mutex_m

        def initialize
          super
          @stdin, @stdout, @stderr, @wait_thread = Open3.popen3("python3", SERVER_PATH)
          wait_for_ready
        end

        def encode(wav_path)
          synchronize do
            raise Error, "Encoder process not running" unless alive?

            send_request(wav_path)
            parse_embedding(read_response)
          end
        end

        def shutdown
          synchronize do
            return unless alive?

            @stdin.puts(JSON.generate(cmd: "shutdown"))
            @stdin.flush
          rescue IOError
            nil
          ensure
            close_io
          end
        end

        def alive?
          @wait_thread&.alive?
        end

        private

        def send_request(wav_path)
          request = JSON.generate(cmd: "encode", id: SecureRandom.hex(4), wav_path: wav_path.to_s)
          @stdin.puts(request)
          @stdin.flush
        end

        def parse_embedding(response)
          raise Error, "Encoder process died" unless response
          raise Error, "Encoder error: #{response["error"]}" if response["error"]

          response["embedding"]
        end

        def wait_for_ready
          response = read_response
          raise Error, "Encoder server failed to start" unless response&.dig("status") == "ready"
        end

        def read_response
          line = @stdout.gets
          return nil unless line

          JSON.parse(line)
        rescue JSON::ParserError
          nil
        end

        def close_io
          @stdin&.close
          @stdout&.close
          @stderr&.close
          @wait_thread&.value
        rescue IOError
          nil
        end
      end
    end
  end
end
