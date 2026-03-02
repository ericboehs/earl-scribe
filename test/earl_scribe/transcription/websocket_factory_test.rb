# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Transcription
    class MessageHandlerTest < Minitest::Test
      test "dispatch calls callback with parsed result" do
        received = nil
        callback = ->(result) { received = result }
        handler = EarlScribe::Transcription::MessageHandler.new(callback)

        json = read_fixture("transcription/deepgram_result.json")
        msg = Minitest::Mock.new
        msg.expect(:data, json)

        handler.dispatch(msg)
        assert_not_nil received
        assert_equal "Hello everyone, welcome to the meeting.", received[:transcript]
        msg.verify
      end

      test "dispatch ignores non-final results" do
        received = nil
        callback = ->(result) { received = result }
        handler = EarlScribe::Transcription::MessageHandler.new(callback)

        msg = Minitest::Mock.new
        msg.expect(:data, '{"type": "Metadata"}')

        handler.dispatch(msg)
        assert_nil received
        msg.verify
      end

      test "dispatch handles nil callback" do
        handler = EarlScribe::Transcription::MessageHandler.new(nil)

        json = read_fixture("transcription/deepgram_result.json")
        msg = Minitest::Mock.new
        msg.expect(:data, json)

        assert_nothing_raised { handler.dispatch(msg) }
        msg.verify
      end

      test "create connects and attaches handlers" do
        events = []
        mock_conn = Object.new
        mock_conn.define_singleton_method(:on) { |event, &_block| events << event }

        handler = EarlScribe::Transcription::MessageHandler.new(proc {})

        WebSocket::Client::Simple.stub(:connect, mock_conn) do
          result = EarlScribe::Transcription::WebsocketFactory.create("wss://example.com", handler)
          assert_same mock_conn, result
        end

        assert_includes events, :message
        assert_includes events, :error
      end
    end
  end
end
