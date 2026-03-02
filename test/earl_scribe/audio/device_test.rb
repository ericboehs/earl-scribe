# frozen_string_literal: true

require "test_helper"
require "open3"

module EarlScribe
  module Audio
    class DeviceTest < Minitest::Test
      test "list parses audio devices from ffmpeg output" do
        with_stubbed_ffmpeg do
          devices = EarlScribe::Audio::Device.list
          assert_equal 3, devices.size
          assert_equal 0, devices[0].index
          assert_equal "MacBook Pro Microphone", devices[0].name
          assert_equal 1, devices[1].index
          assert_equal "Meeting", devices[1].name
          assert_equal 2, devices[2].index
          assert_equal "ZoomAudioDevice", devices[2].name
        end
      end

      test "list returns empty array when no audio section" do
        with_stubbed_ffmpeg("no devices here\n") do
          assert_equal [], EarlScribe::Audio::Device.list
        end
      end

      test "resolve returns DeviceInfo for numeric input" do
        device = EarlScribe::Audio::Device.resolve("3")
        assert_equal 3, device.index
        assert_equal "3", device.name
      end

      test "resolve finds device by name" do
        with_stubbed_ffmpeg do
          device = EarlScribe::Audio::Device.resolve("Meeting")
          assert_equal 1, device.index
          assert_equal "Meeting", device.name
        end
      end

      test "resolve is case insensitive" do
        with_stubbed_ffmpeg do
          device = EarlScribe::Audio::Device.resolve("meeting")
          assert_equal 1, device.index
        end
      end

      test "resolve raises Error when device not found" do
        with_stubbed_ffmpeg do
          error = assert_raises(EarlScribe::Error) { EarlScribe::Audio::Device.resolve("Nonexistent") }
          assert_includes error.message, "Nonexistent"
        end
      end

      test "DeviceInfo is a Struct with index and name" do
        info = EarlScribe::Audio::Device::DeviceInfo.new(index: 5, name: "Test")
        assert_equal 5, info.index
        assert_equal "Test", info.name
      end

      private

      def with_stubbed_ffmpeg(output = nil, &block)
        stderr = output || read_fixture("audio/ffmpeg_devices.txt")
        Open3.stub(:capture3, ["", stderr, nil], &block)
      end
    end
  end
end
