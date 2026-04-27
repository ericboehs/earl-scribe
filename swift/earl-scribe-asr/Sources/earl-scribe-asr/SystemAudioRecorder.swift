import AVFoundation
import Foundation
import ScreenCaptureKit

/// Captures system audio (everything other apps are playing) via ScreenCaptureKit.
/// Emits 16 kHz mono Float32 chunks through `onChunk`. Requires Screen Recording
/// permission. macOS 13+ (we require 14+).
final class SystemAudioRecorder: NSObject, @unchecked Sendable {
    var onChunk: (([Float]) -> Void)?

    private var stream: SCStream?
    private var isRecording = false
    private let targetSampleRate: Int = 16_000
    private let targetChannelCount: Int = 1

    func start() async throws {
        guard !isRecording else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw SystemAudioRecorderError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = targetSampleRate
        config.channelCount = targetChannelCount
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try await newStream.startCapture()

        stream = newStream
        isRecording = true
    }

    func stop() async {
        guard isRecording else { return }
        try? await Task.sleep(nanoseconds: 200_000_000)
        if let stream { try? await stream.stopCapture() }
        stream = nil
        isRecording = false
    }
}

extension SystemAudioRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio,
              sampleBuffer.isValid, sampleBuffer.numSamples > 0,
              let formatDescription = sampleBuffer.formatDescription,
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let blockBuffer = sampleBuffer.dataBuffer else { return }

        let asbd = asbdPointer.pointee
        let sourceChannels = Int(asbd.mChannelsPerFrame)
        let length = CMBlockBufferGetDataLength(blockBuffer)
        guard length > 0, sourceChannels > 0 else { return }

        var dataPointer: UnsafeMutablePointer<Int8>?
        var lengthAtOffset = 0
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                                 lengthAtOffsetOut: &lengthAtOffset,
                                                 totalLengthOut: nil,
                                                 dataPointerOut: &dataPointer)
        guard status == noErr, let ptr = dataPointer else { return }

        let floatPointer = UnsafeRawPointer(ptr).bindMemory(
            to: Float.self, capacity: length / MemoryLayout<Float>.stride
        )
        let totalFloats = length / MemoryLayout<Float>.stride

        let mono: [Float]
        if sourceChannels == 1 {
            mono = Array(UnsafeBufferPointer(start: floatPointer, count: totalFloats))
        } else {
            let frames = totalFloats / sourceChannels
            var out = [Float](repeating: 0, count: frames)
            for f in 0..<frames {
                var sum: Float = 0
                for c in 0..<sourceChannels {
                    sum += floatPointer[f * sourceChannels + c]
                }
                out[f] = sum / Float(sourceChannels)
            }
            mono = out
        }

        onChunk?(mono)
    }
}

extension SystemAudioRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        FileHandle.standardError.write(Data(
            "SystemAudioRecorder: stream stopped with error — \(error.localizedDescription)\n".utf8
        ))
        isRecording = false
    }
}

enum SystemAudioRecorderError: Error, LocalizedError {
    case noDisplayAvailable

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable: return "No display available for system audio capture."
        }
    }
}
