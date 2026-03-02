# frozen_string_literal: true

require "test_helper"

module EarlScribe
  module Cli
    class DevicesTest < Minitest::Test
      test "run lists devices" do
        devices = [
          EarlScribe::Audio::Device::DeviceInfo.new(index: 0, name: "Mic"),
          EarlScribe::Audio::Device::DeviceInfo.new(index: 1, name: "Meeting")
        ]
        EarlScribe::Audio::Device.stub(:list, devices) do
          stdout, _stderr = capture_io { EarlScribe::Cli::Devices.run([]) }
          assert_includes stdout, "[0] Mic"
          assert_includes stdout, "[1] Meeting"
          assert_includes stdout, "Audio input devices:"
        end
      end

      test "run warns when no devices found" do
        EarlScribe::Audio::Device.stub(:list, []) do
          _stdout, stderr = capture_io { EarlScribe::Cli::Devices.run([]) }
          assert_includes stderr, "No audio devices found"
        end
      end
    end
  end
end
