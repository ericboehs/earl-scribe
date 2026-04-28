import Foundation
import AVFoundation
import WhisperKit
import CoreML

/// Minimal AudioProcessing conformer that pulls Float32 16k mono PCM from stdin
/// and exposes it via `audioSamples` for AudioStreamTranscriber.
final class StdinAudioProcessor: NSObject, AudioProcessing {

    // MARK: - Mutable state (protected by `lock`)
    private let lock = NSLock()
    private var samples = ContiguousArray<Float>()
    private var energies: [Float] = []
    private var reading = false
    private var readerThread: Thread?
    private var sampleCallback: (([Float]) -> Void)?

    // MARK: - AudioProcessing storage
    var audioSamples: ContiguousArray<Float> {
        lock.lock(); defer { lock.unlock() }
        return samples
    }
    var relativeEnergy: [Float] {
        lock.lock(); defer { lock.unlock() }
        return energies
    }
    var relativeEnergyWindow: Int = 20

    func purgeAudioSamples(keepingLast keep: Int) {
        lock.lock(); defer { lock.unlock() }
        if samples.count > keep {
            samples.removeFirst(samples.count - keep)
        }
    }

    // MARK: - Stdin reader
    func startRecordingLive(inputDeviceID: DeviceID? = nil, callback: (([Float]) -> Void)?) throws {
        lock.lock()
        guard !reading else { lock.unlock(); return }
        reading = true
        sampleCallback = callback
        lock.unlock()

        let thread = Thread { [weak self] in self?.readLoop() }
        thread.name = "stdin-pcm-reader"
        thread.start()
        self.readerThread = thread
    }

    func resumeRecordingLive(inputDeviceID: DeviceID? = nil, callback: (([Float]) -> Void)?) throws {
        try startRecordingLive(inputDeviceID: inputDeviceID, callback: callback)
    }

    func startStreamingRecordingLive(inputDeviceID: DeviceID? = nil) -> (AsyncThrowingStream<[Float], Error>, AsyncThrowingStream<[Float], Error>.Continuation) {
        AsyncThrowingStream.makeStream(of: [Float].self)
    }

    func pauseRecording() {
        lock.lock(); reading = false; lock.unlock()
    }

    func stopRecording() {
        lock.lock(); reading = false; lock.unlock()
    }

    /// Set when stdin reaches EOF; the main process can poll `eofReached` to
    /// shut down the AudioStreamTranscriber loop after the buffer drains.
    private(set) var eofReached: Bool = false

    private func readLoop() {
        let frameSize = 1600          // 100ms at 16kHz
        let bytesNeeded = frameSize * MemoryLayout<Float>.size
        var buffer = Data()
        buffer.reserveCapacity(bytesNeeded)
        let stdin = FileHandle.standardInput

        while true {
            lock.lock(); let stillReading = reading; lock.unlock()
            if !stillReading { break }

            let need = bytesNeeded - buffer.count
            let chunk: Data
            do {
                chunk = try stdin.read(upToCount: need) ?? Data()
            } catch {
                break
            }
            if chunk.isEmpty {
                lock.lock(); eofReached = true; lock.unlock()
                break
            }
            buffer.append(chunk)
            guard buffer.count >= bytesNeeded else { continue }

            let floats = buffer.withUnsafeBytes { raw -> [Float] in
                let ptr = raw.bindMemory(to: Float.self)
                return Array(ptr.prefix(frameSize))
            }
            buffer.removeFirst(bytesNeeded)

            lock.lock()
            samples.append(contentsOf: floats)
            let energy = AudioProcessor.calculateRelativeEnergy(of: floats, relativeTo: nil)
            energies.append(energy)
            if energies.count > 4096 { energies.removeFirst(energies.count - 4096) }
            let cb = sampleCallback
            lock.unlock()

            cb?(floats)
        }
    }

    // MARK: - Static delegates to default AudioProcessor

    static func loadAudio(fromPath audioFilePath: String, channelMode: ChannelMode, startTime: Double?, endTime: Double?, maxReadFrameSize: AVAudioFrameCount?) throws -> AVAudioPCMBuffer {
        try AudioProcessor.loadAudio(fromPath: audioFilePath, channelMode: channelMode, startTime: startTime, endTime: endTime, maxReadFrameSize: maxReadFrameSize)
    }

    static func loadAudio(at audioPaths: [String], channelMode: ChannelMode) async -> [Result<[Float], Swift.Error>] {
        await AudioProcessor.loadAudio(at: audioPaths, channelMode: channelMode)
    }

    static func padOrTrimAudio(fromArray audioArray: [Float], startAt startIndex: Int, toLength frameLength: Int, saveSegment: Bool) -> MLMultiArray? {
        AudioProcessor.padOrTrimAudio(fromArray: audioArray, startAt: startIndex, toLength: frameLength, saveSegment: saveSegment)
    }

    func padOrTrim(fromArray audioArray: [Float], startAt startIndex: Int, toLength frameLength: Int) -> (any AudioProcessorOutputType)? {
        AudioProcessor.padOrTrimAudio(fromArray: audioArray, startAt: startIndex, toLength: frameLength, saveSegment: false)
    }
}
