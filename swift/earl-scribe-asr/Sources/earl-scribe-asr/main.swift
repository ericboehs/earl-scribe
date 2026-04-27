import ArgumentParser
import AVFoundation
import FluidAudio
import Foundation

@main
struct EarlScribeASR: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "earl-scribe-asr",
        abstract: "Local streaming ASR via FluidAudio Parakeet EOU. Emits JSONL on stdout."
    )

    @Option(name: .long, help: "Audio file to transcribe (any format). Mutually exclusive with --stdin.")
    var file: String?

    @Flag(name: .long, help: "Read raw PCM from stdin until EOF.")
    var stdin: Bool = false

    @Option(name: .long, help: "Stdin sample format: f32_16k_mono or s16_48k_mono. Default f32_16k_mono.")
    var stdinFormat: String = "f32_16k_mono"

    @Option(name: .long, help: "Chunk size in ms: 160, 320, or 1280. Default 320.")
    var chunkMs: Int = 320

    @Option(name: .long, help: "Simulated live feed size in ms (--file only). Default 1000.")
    var feedMs: Int = 1000

    @Option(name: .long, help: "Stdin read slice size in ms. Default 100.")
    var stdinSliceMs: Int = 100

    @Flag(name: .long, help: "Decode file at real-time pace instead of as fast as possible. (--file only)")
    var realtime: Bool = false

    @Flag(name: .long, help: "Suppress partial/eou events; only emit final.")
    var quiet: Bool = false

    @Option(name: .long, help: "Force-flush an utterance after this many seconds of unbroken speech. Default 4.0.")
    var maxUtteranceSec: Double = 4.0

    mutating func run() async throws {
        _ = Self.wallStart  // force timer init at process start

        let chunkSize: StreamingChunkSize
        switch chunkMs {
        case 160: chunkSize = .ms160
        case 320: chunkSize = .ms320
        case 1280: chunkSize = .ms1280
        default:
            emit(["type": "error", "message": "invalid chunk-ms: must be 160, 320, or 1280"])
            throw ExitCode.validationFailure
        }

        if stdin && file != nil {
            emit(["type": "error", "message": "pass either --file or --stdin, not both"])
            throw ExitCode.validationFailure
        }
        if !stdin && file == nil {
            emit(["type": "error", "message": "must pass --file <path> or --stdin"])
            throw ExitCode.validationFailure
        }

        if stdin {
            try await runStdin(chunkSize: chunkSize)
        } else {
            try await runFile(chunkSize: chunkSize)
        }
    }

    private func runFile(chunkSize: StreamingChunkSize) async throws {
        let path = file!
        let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            emit(["type": "error", "message": "file not found: \(fileURL.path)"])
            throw ExitCode.failure
        }

        let audioFile = try AVAudioFile(forReading: fileURL)
        let audioDurationSec = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        emit([
            "type": "start",
            "mode": "file",
            "file": fileURL.lastPathComponent,
            "chunk_ms": chunkMs,
            "audio_duration_sec": audioDurationSec,
            "source_sample_rate": audioFile.processingFormat.sampleRate,
            "source_channels": Int(audioFile.processingFormat.channelCount)
        ])

        let manager = StreamingEouAsrManager(chunkSize: chunkSize)
        try await loadAndWireCallbacks(manager: manager)

        let feedFrames = AVAudioFrameCount(
            Double(feedMs) / 1000.0 * audioFile.processingFormat.sampleRate
        )
        let format = audioFile.processingFormat

        let runStart = Date()
        var audioClockSec = 0.0
        var samplesSinceFlush = 0

        while audioFile.framePosition < audioFile.length {
            guard let slice = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: feedFrames) else {
                emit(["type": "error", "message": "failed to allocate buffer"])
                throw ExitCode.failure
            }
            try audioFile.read(into: slice, frameCount: feedFrames)
            if slice.frameLength == 0 { break }
            let sliceFrames = slice.frameLength

            try await manager.appendAudio(slice)
            let sliceSec = Double(sliceFrames) / format.sampleRate
            audioClockSec += sliceSec
            Self.setAudioSec(audioClockSec)
            try await manager.processBufferedAudio()
            samplesSinceFlush += Int(sliceFrames)
            if await manager.eouDetected {
                await manager.reset()
                samplesSinceFlush = 0
            } else if Double(samplesSinceFlush) / format.sampleRate >= maxUtteranceSec {
                await manager.injectSilence(2.0)
                try await manager.processBufferedAudio()
                if await manager.eouDetected {
                    await manager.reset()
                }
                samplesSinceFlush = 0
            }

            if realtime {
                let elapsed = Date().timeIntervalSince(runStart)
                let lag = audioClockSec - elapsed
                if lag > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(lag * 1_000_000_000))
                }
            }
        }

        let finalText = try await manager.finish()
        let wall = Date().timeIntervalSince(runStart)
        let rtfx = audioDurationSec / max(wall, 0.0001)

        emit([
            "type": "final",
            "text": finalText,
            "audio_duration_sec": audioDurationSec,
            "wall_sec": wall,
            "rtfx": rtfx
        ])

        await manager.cleanup()
    }

    private func runStdin(chunkSize: StreamingChunkSize) async throws {
        let sampleRate: Double
        let commonFormat: AVAudioCommonFormat
        let bytesPerFrame: Int
        switch stdinFormat {
        case "f32_16k_mono":
            sampleRate = 16_000.0
            commonFormat = .pcmFormatFloat32
            bytesPerFrame = MemoryLayout<Float32>.size
        case "s16_48k_mono":
            sampleRate = 48_000.0
            commonFormat = .pcmFormatInt16
            bytesPerFrame = MemoryLayout<Int16>.size
        default:
            emit(["type": "error", "message": "invalid --stdin-format: \(stdinFormat)"])
            throw ExitCode.validationFailure
        }

        guard let format = AVAudioFormat(
            commonFormat: commonFormat,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            emit(["type": "error", "message": "failed to create stdin audio format"])
            throw ExitCode.failure
        }

        emit([
            "type": "start",
            "mode": "stdin",
            "stdin_format": stdinFormat,
            "chunk_ms": chunkMs,
            "source_sample_rate": sampleRate,
            "source_channels": 1
        ])

        let manager = StreamingEouAsrManager(chunkSize: chunkSize)
        try await loadAndWireCallbacks(manager: manager)

        let sliceFrames = AVAudioFrameCount(Double(stdinSliceMs) / 1000.0 * sampleRate)
        let sliceBytes = Int(sliceFrames) * bytesPerFrame

        let stdinHandle = FileHandle.standardInput
        var leftover = Data()
        var totalFrames: Int = 0
        var samplesSinceFlush = 0
        let runStart = Date()

        while true {
            let chunk = stdinHandle.availableData
            if chunk.isEmpty {
                break
            }
            leftover.append(chunk)

            while leftover.count >= sliceBytes {
                let sliceData = leftover.prefix(sliceBytes)
                leftover.removeFirst(sliceBytes)

                guard let buffer = Self.makePcmBuffer(
                    format: format, frames: sliceFrames, data: sliceData
                ) else {
                    emit(["type": "error", "message": "failed to allocate stdin buffer"])
                    throw ExitCode.failure
                }
                try await manager.appendAudio(buffer)
                totalFrames += Int(sliceFrames)
                samplesSinceFlush += Int(sliceFrames)
                Self.setAudioSec(Double(totalFrames) / sampleRate)
                try await manager.processBufferedAudio()
                if await manager.eouDetected {
                    await manager.reset()
                    samplesSinceFlush = 0
                } else if Double(samplesSinceFlush) / sampleRate >= maxUtteranceSec {
                    await manager.injectSilence(2.0)
                    try await manager.processBufferedAudio()
                    if await manager.eouDetected {
                        await manager.reset()
                    }
                    samplesSinceFlush = 0
                }
            }
        }

        if leftover.count >= bytesPerFrame {
            let tailFrames = AVAudioFrameCount(leftover.count / bytesPerFrame)
            if let buffer = Self.makePcmBuffer(
                format: format, frames: tailFrames, data: leftover
            ) {
                try await manager.appendAudio(buffer)
                totalFrames += Int(tailFrames)
                Self.setAudioSec(Double(totalFrames) / sampleRate)
                try await manager.processBufferedAudio()
                if await manager.eouDetected {
                    await manager.reset()
                }
            }
        }

        let finalText = try await manager.finish()
        let wall = Date().timeIntervalSince(runStart)
        let audioDurationSec = Double(totalFrames) / sampleRate
        let rtfx = audioDurationSec / max(wall, 0.0001)

        emit([
            "type": "final",
            "text": finalText,
            "audio_duration_sec": audioDurationSec,
            "wall_sec": wall,
            "rtfx": rtfx
        ])

        await manager.cleanup()
    }

    private static func makePcmBuffer(
        format: AVAudioFormat,
        frames: AVAudioFrameCount,
        data: Data
    ) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames
        let frameCount = Int(frames)
        if let channel = buffer.floatChannelData?[0] {
            data.withUnsafeBytes { rawBuf in
                let src = rawBuf.bindMemory(to: Float32.self)
                for i in 0..<frameCount {
                    channel[i] = src[i]
                }
            }
        } else if let channel = buffer.int16ChannelData?[0] {
            data.withUnsafeBytes { rawBuf in
                let src = rawBuf.bindMemory(to: Int16.self)
                for i in 0..<frameCount {
                    channel[i] = src[i]
                }
            }
        }
        return buffer
    }

    private func loadAndWireCallbacks(manager: StreamingEouAsrManager) async throws {
        let loadStart = Date()
        try await manager.loadModels()
        emit(["type": "models_loaded", "elapsed_sec": Date().timeIntervalSince(loadStart)])

        if !quiet {
            await manager.setPartialCallback { text in
                Self.emitStatic([
                    "type": "partial",
                    "text": text,
                    "wall_ms": Self.wallMs()
                ])
            }
            await manager.setEouCallback { text in
                Self.emitStatic([
                    "type": "eou",
                    "text": text,
                    "audio_sec": Self.readAudioSec(),
                    "wall_ms": Self.wallMs()
                ])
            }
        }
    }

    // MARK: - JSONL emit

    private static let wallStart = Date()
    private static func wallMs() -> Int { Int(Date().timeIntervalSince(wallStart) * 1000) }

    private static let audioSecLock = NSLock()
    nonisolated(unsafe) private static var audioSecCursor: Double = 0
    private static func setAudioSec(_ value: Double) {
        audioSecLock.lock(); defer { audioSecLock.unlock() }
        audioSecCursor = value
    }
    private static func readAudioSec() -> Double {
        audioSecLock.lock(); defer { audioSecLock.unlock() }
        return audioSecCursor
    }

    private static let stdoutLock = NSLock()
    private static func emitStatic(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        stdoutLock.lock()
        defer { stdoutLock.unlock() }
        print(line)
        fflush(stdout)
    }
    private func emit(_ payload: [String: Any]) { Self.emitStatic(payload) }
}
