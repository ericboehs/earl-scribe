# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Transcription
    class DeepgramTest < Minitest::Test
      test "initializes with required api_key" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "test-key")
        assert_equal "test-key", client.api_key
      end

      test "defaults to stereo channels" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        assert_equal 2, client.channels
      end

      test "mono channels" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key", channels: 1)
        assert_equal 1, client.channels
      end

      test "default sample rate is 16000" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        assert_equal 16_000, client.sample_rate
      end

      test "websocket_url includes api params" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        url = client.websocket_url

        assert url.start_with?("wss://api.deepgram.com/v1/listen?")
        assert_includes url, "model=nova-3"
        assert_includes url, "diarize=true"
        assert_includes url, "encoding=linear16"
        assert_includes url, "sample_rate=16000"
        assert_includes url, "channels=2"
        assert_includes url, "multichannel=true"
      end

      test "mono url does not include multichannel" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key", channels: 1)
        url = client.websocket_url

        assert_not_includes url, "multichannel"
        assert_includes url, "channels=1"
      end

      test "params includes all required fields" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        params = client.params

        assert_equal "nova-3", params["model"]
        assert_equal "en-US", params["language"]
        assert_equal "true", params["punctuate"]
        assert_equal "true", params["smart_format"]
        assert_equal "true", params["diarize"]
        assert_equal "linear16", params["encoding"]
      end

      test "params includes mip_opt_out when enabled" do
        EarlScribe::Config.stub(:deepgram_mip_opt_out?, true) do
          client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
          assert_equal "true", client.params["mip_opt_out"]
          assert_includes client.websocket_url, "mip_opt_out=true"
        end
      end

      test "params excludes mip_opt_out when disabled" do
        EarlScribe::Config.stub(:deepgram_mip_opt_out?, false) do
          client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
          assert_nil client.params["mip_opt_out"]
          assert_not_includes client.websocket_url, "mip_opt_out"
        end
      end

      test "connect raises error without api key" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: nil)
        error = assert_raises(EarlScribe::Error) { client.connect(proc {}) }
        assert_includes error.message, "DEEPGRAM_API_KEY"
      end

      test "send_audio handles nil connection" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        assert_nothing_raised { client.send_audio("data") }
      end

      test "close handles nil connection" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        assert_nothing_raised { client.close }
      end

      test "connect creates handler and connection" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        mock_conn = mock_websocket

        EarlScribe::Transcription::WebsocketFactory.stub(:create, mock_conn) do
          client.connect(proc {})
        end

        assert_not_nil client.instance_variable_get(:@connection)
      end

      test "send_audio delegates to connection" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        sent = []
        mock_conn = Object.new
        mock_conn.define_singleton_method(:send) { |data, **_opts| sent << data }

        client.instance_variable_set(:@connection, mock_conn)
        client.send_audio("audio_data")
        assert_equal ["audio_data"], sent
      end

      test "close sends CloseStream and closes connection" do
        client = EarlScribe::Transcription::Deepgram.new(api_key: "key")
        messages = []
        closed = false
        mock_conn = Object.new
        mock_conn.define_singleton_method(:send) { |data, **_opts| messages << data }
        mock_conn.define_singleton_method(:close) { closed = true }

        client.instance_variable_set(:@connection, mock_conn)
        client.close

        assert_equal 1, messages.size
        assert_includes messages.first, "CloseStream"
        assert closed
      end

      test "error handler suppresses stream closed errors" do
        handlers = {}
        mock_conn = Object.new
        mock_conn.define_singleton_method(:on) { |event, &block| handlers[event] = block }

        WebSocket::Client::Simple.stub(:connect, mock_conn) do
          WebsocketFactory.create("wss://example.com", MessageHandler.new(proc {}))
        end

        error = IOError.new("stream closed in another thread")
        logged = []
        logger = Logger.new(StringIO.new)
        logger.define_singleton_method(:error) { |msg| logged << msg }

        EarlScribe.stub(:logger, logger) do
          handlers[:error].call(error)
        end

        assert_empty logged
      end

      test "error handler logs real errors" do
        handlers = {}
        mock_conn = Object.new
        mock_conn.define_singleton_method(:on) { |event, &block| handlers[event] = block }

        WebSocket::Client::Simple.stub(:connect, mock_conn) do
          WebsocketFactory.create("wss://example.com", MessageHandler.new(proc {}))
        end

        error = RuntimeError.new("connection refused")
        logged = []
        logger = Logger.new(StringIO.new)
        logger.define_singleton_method(:error) { |msg| logged << msg }

        EarlScribe.stub(:logger, logger) do
          handlers[:error].call(error)
        end

        assert_includes logged.first, "connection refused"
      end

      private

      def mock_websocket
        conn = Object.new
        conn.define_singleton_method(:on) { |_event, &_block| nil }
        conn
      end
    end
  end
end
