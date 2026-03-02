# frozen_string_literal: true

require "json"
require "websocket-client-simple"

module EarlScribe
  module Transcription
    # WebSocket streaming client for Deepgram Nova-3 real-time transcription
    class Deepgram
      WEBSOCKET_URL = "wss://api.deepgram.com/v1/listen"

      attr_reader :api_key, :sample_rate, :channels

      def initialize(api_key:, channels: 2, sample_rate: 16_000)
        @api_key = api_key
        @channels = channels
        @sample_rate = sample_rate
        @connection = nil
      end

      def connect(callback)
        raise Error, "DEEPGRAM_API_KEY is required" unless api_key

        handler = MessageHandler.new(callback)
        @connection = WebsocketFactory.create(websocket_url, handler, headers: auth_headers)
      end

      def send_audio(data)
        @connection&.send(data, type: :binary)
      end

      def close
        @connection&.send(JSON.generate(type: "CloseStream"), type: :text)
        @connection&.close
        @connection = nil
      end

      def websocket_url
        query = params.map { |key, val| "#{key}=#{val}" }.join("&")
        "#{WEBSOCKET_URL}?#{query}"
      end

      def params
        base = base_params
        base["multichannel"] = "true" if channels > 1
        base["mip_opt_out"] = "true" if Config.deepgram_mip_opt_out?
        base
      end

      private

      def base_params
        {
          "model" => "nova-3", "language" => "en-US", "punctuate" => "true",
          "smart_format" => "true", "diarize" => "true", "encoding" => "linear16",
          "sample_rate" => sample_rate.to_s, "channels" => channels.to_s
        }
      end

      def auth_headers
        { "Authorization" => "Token #{api_key}" }
      end
    end

    # Creates and configures WebSocket connections with message/error handlers
    module WebsocketFactory
      def self.create(url, handler, headers: {})
        connection = WebSocket::Client::Simple.connect(url, headers: headers)
        attach_handlers(connection, handler)
        connection
      end

      def self.attach_handlers(connection, handler)
        connection.on(:message) { |msg| handler.dispatch(msg) }
        connection.on(:error) do |err|
          EarlScribe.logger.error("Deepgram error: #{err.message}") unless err.message.include?("stream closed")
        end
      end

      private_class_method :attach_handlers
    end

    # Dispatches incoming Deepgram WebSocket messages to a callback
    class MessageHandler
      def initialize(callback)
        @callback = callback
      end

      def dispatch(msg)
        result = ResultParser.parse(msg.data)
        @callback&.call(result) if result
      end
    end
  end
end
