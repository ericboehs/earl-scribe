import AVFoundation
import CoreAudio
import Foundation

/// Captures mic audio via AVAudioEngine and emits 16 kHz mono Float32 chunks.
/// No external sox/ffmpeg subprocess.
final class MicRecorder: @unchecked Sendable {
    var onChunk: (([Float]) -> Void)?

    private var engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    private lazy var targetFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                      channels: 1, interleaved: false)!
    }()

    func start() throws {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw MicRecorderError.noInputAvailable
        }

        let bufferDuration = 0.02  // 20ms
        let bufferSize = max(1, AVAudioFrameCount(hwFormat.sampleRate * bufferDuration))

        lock.lock()
        converter = nil
        converterSourceFormat = nil
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hwFormat) { [weak self] pcm, _ in
            guard let self else { return }
            if pcm.format.channelCount > 2 {
                self.convertWithManualDownmix(buffer: pcm)
            } else if let conv = self.converter(for: pcm.format) {
                self.convert(buffer: pcm, using: conv)
            }
        }

        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func converter(for sourceFormat: AVAudioFormat) -> AVAudioConverter? {
        lock.lock(); defer { lock.unlock() }
        if let cached = converter, let cachedSource = converterSourceFormat,
           cachedSource.sampleRate == sourceFormat.sampleRate,
           cachedSource.channelCount == sourceFormat.channelCount {
            return cached
        }
        let conv = AVAudioConverter(from: sourceFormat, to: targetFormat)
        converter = conv
        converterSourceFormat = sourceFormat
        return conv
    }

    private func convert(buffer: AVAudioPCMBuffer, using conv: AVAudioConverter) {
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * (targetFormat.sampleRate / buffer.format.sampleRate)
        ) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

        var error: NSError?
        let consumed = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        consumed.initialize(to: false)
        defer { consumed.deinitialize(count: 1); consumed.deallocate() }
        let bufferPtr = Unmanaged.passUnretained(buffer)
        conv.convert(to: out, error: &error) { _, status in
            if consumed.pointee { status.pointee = .noDataNow; return nil }
            consumed.pointee = true
            status.pointee = .haveData
            return bufferPtr.takeUnretainedValue()
        }
        if error != nil { return }

        guard let channelData = out.floatChannelData, out.frameLength > 0 else { return }
        let frames = Array(UnsafeBufferPointer(start: channelData[0], count: Int(out.frameLength)))
        onChunk?(frames)
    }

    private func convertWithManualDownmix(buffer: AVAudioPCMBuffer) {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0,
              let channelData = buffer.floatChannelData else { return }

        var mono = [Float](repeating: 0, count: frameLength)
        for f in 0..<frameLength {
            var sum: Float = 0
            for c in 0..<channelCount { sum += channelData[c][f] }
            mono[f] = sum / Float(channelCount)
        }

        let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: buffer.format.sampleRate,
                                       channels: 1, interleaved: false)!
        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat,
                                                frameCapacity: AVAudioFrameCount(frameLength)) else {
            return
        }
        monoBuffer.frameLength = AVAudioFrameCount(frameLength)
        if let dest = monoBuffer.floatChannelData?[0] {
            mono.withUnsafeBufferPointer { src in
                dest.update(from: src.baseAddress!, count: frameLength)
            }
        }

        if let conv = converter(for: monoFormat) {
            convert(buffer: monoBuffer, using: conv)
        }
    }
}

enum MicRecorderError: Error, LocalizedError {
    case noInputAvailable

    var errorDescription: String? {
        switch self {
        case .noInputAvailable: return "No mic input available."
        }
    }
}
