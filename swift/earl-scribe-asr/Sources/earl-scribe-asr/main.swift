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

    @Flag(name: .long, inversion: .prefixedNo,
          help: "Run Sortformer diarization in parallel and tag EOU events with speaker IDs.")
    var diarize: Bool = true

    @Flag(name: .long, help: "Emit per-EOU diarizer state on stderr (frames, speaker count, dominant id).")
    var diarDebug: Bool = false

    mutating func run() async throws {
        _ = Self.wallStart  // force timer init at process start
        Self.diarDebugEnabled = diarDebug

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
        let diarizer = try await loadDiarizerIfEnabled()

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

            let diarSamples = diarizer == nil ? [] : Self.floatsFromBuffer(slice)
            let diarRate = format.sampleRate
            try await manager.appendAudio(slice)
            try Self.feedDiarizer(diarizer, samples: diarSamples, sourceRate: diarRate)
            let sliceSec = Double(sliceFrames) / format.sampleRate
            audioClockSec += sliceSec
            Self.setAudioSec(audioClockSec)
            try await manager.processBufferedAudio()
            _ = try? diarizer?.process()
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
            Self.drainPendingEous(diarizer: diarizer, force: false)

            if realtime {
                let elapsed = Date().timeIntervalSince(runStart)
                let lag = audioClockSec - elapsed
                if lag > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(lag * 1_000_000_000))
                }
            }
        }

        let finalText = try await manager.finish()
        _ = try? diarizer?.finalizeSession()
        Self.drainPendingEous(diarizer: diarizer, force: true)
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
        diarizer?.cleanup()
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
        let diarizer = try await loadDiarizerIfEnabled()

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
                let diarSamples = diarizer == nil ? [] : Self.floatsFromBuffer(buffer)
                try await manager.appendAudio(buffer)
                try Self.feedDiarizer(diarizer, samples: diarSamples, sourceRate: sampleRate)
                totalFrames += Int(sliceFrames)
                samplesSinceFlush += Int(sliceFrames)
                Self.setAudioSec(Double(totalFrames) / sampleRate)
                try await manager.processBufferedAudio()
                _ = try? diarizer?.process()
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
                Self.drainPendingEous(diarizer: diarizer, force: false)
            }
        }

        if leftover.count >= bytesPerFrame {
            let tailFrames = AVAudioFrameCount(leftover.count / bytesPerFrame)
            if let buffer = Self.makePcmBuffer(
                format: format, frames: tailFrames, data: leftover
            ) {
                let diarSamples = diarizer == nil ? [] : Self.floatsFromBuffer(buffer)
                try await manager.appendAudio(buffer)
                try Self.feedDiarizer(diarizer, samples: diarSamples, sourceRate: sampleRate)
                totalFrames += Int(tailFrames)
                Self.setAudioSec(Double(totalFrames) / sampleRate)
                try await manager.processBufferedAudio()
                _ = try? diarizer?.process()
                if await manager.eouDetected {
                    await manager.reset()
                }
            }
        }

        let finalText = try await manager.finish()
        _ = try? diarizer?.finalizeSession()
        Self.drainPendingEous(diarizer: diarizer, force: true)
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
        diarizer?.cleanup()
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
                let endSec = Self.readAudioSec()
                let startSec = Self.consumeLastEouEnd(updatingTo: endSec)
                Self.pushPendingEou(text: text, startSec: startSec, endSec: endSec)
            }
        }
    }

    private func loadDiarizerIfEnabled() async throws -> SortformerDiarizer? {
        guard diarize else { return nil }
        let loadStart = Date()
        let config = SortformerConfig.balancedV2
        let timelineConfig = DiarizerTimelineConfig.sortformerDefault
        let diarizer = SortformerDiarizer(config: config, timelineConfig: timelineConfig)
        do {
            let models = try await SortformerModels.loadFromHuggingFace(config: config)
            diarizer.initialize(models: models)
            FileHandle.standardError.write(Data(
                "diarizer_loaded balancedV2 elapsed_sec=\(Date().timeIntervalSince(loadStart))\n".utf8
            ))
            return diarizer
        } catch {
            FileHandle.standardError.write(Data(
                "Sortformer load failed: \(error.localizedDescription); diarization disabled\n".utf8
            ))
            return nil
        }
    }

    private static func feedDiarizer(_ diarizer: SortformerDiarizer?, samples: [Float], sourceRate: Double) throws {
        guard let diarizer = diarizer else { return }
        try diarizer.addAudio(samples, sourceSampleRate: sourceRate)
    }

    private static func floatsFromBuffer(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        var samples = [Float](repeating: 0, count: frames)
        if let ch = buffer.floatChannelData?[0] {
            for i in 0..<frames { samples[i] = ch[i] }
        } else if let ch = buffer.int16ChannelData?[0] {
            for i in 0..<frames { samples[i] = Float(ch[i]) / 32768.0 }
        }
        return samples
    }

    private static func dominantSpeaker(diarizer: SortformerDiarizer, startSec: Double, endSec: Double) -> Int? {
        let timeline = diarizer.timeline
        let frameDur = Double(timeline.config.frameDurationSeconds)
        var bestSpeaker: Int? = nil
        var bestOverlap = 0.0
        for (idx, speaker) in timeline.speakers {
            var overlap = 0.0
            for seg in speaker.finalizedSegments {
                overlap += overlapSec(segStart: Double(seg.startFrame) * frameDur,
                                      segEnd: Double(seg.endFrame) * frameDur,
                                      startSec: startSec, endSec: endSec)
            }
            for seg in speaker.tentativeSegments {
                overlap += overlapSec(segStart: Double(seg.startFrame) * frameDur,
                                      segEnd: Double(seg.endFrame) * frameDur,
                                      startSec: startSec, endSec: endSec)
            }
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = idx
            }
        }
        return bestSpeaker
    }

    private static func overlapSec(segStart: Double, segEnd: Double, startSec: Double, endSec: Double) -> Double {
        let lo = max(segStart, startSec)
        let hi = min(segEnd, endSec)
        return hi > lo ? hi - lo : 0.0
    }

    // MARK: - Pending EOU queue

    private struct PendingEou {
        let text: String
        let startSec: Double
        let endSec: Double
        let wallMs: Int
    }

    private static let pendingLock = NSLock()
    nonisolated(unsafe) private static var pendingEous: [PendingEou] = []
    nonisolated(unsafe) private static var lastEouEndSec: Double = 0.0
    nonisolated(unsafe) private static var diarDebugEnabled: Bool = false

    private static func consumeLastEouEnd(updatingTo endSec: Double) -> Double {
        pendingLock.lock(); defer { pendingLock.unlock() }
        let start = lastEouEndSec
        lastEouEndSec = endSec
        return start
    }

    private static func pushPendingEou(text: String, startSec: Double, endSec: Double) {
        pendingLock.lock(); defer { pendingLock.unlock() }
        pendingEous.append(PendingEou(text: text, startSec: startSec, endSec: endSec, wallMs: wallMs()))
    }

    private static func drainPendingEous(diarizer: SortformerDiarizer?, force: Bool) {
        pendingLock.lock()
        let snapshot = pendingEous
        pendingEous = []
        pendingLock.unlock()

        var stillPending: [PendingEou] = []
        for eou in snapshot {
            if let diarizer = diarizer, !force {
                let frameDur = Double(diarizer.timeline.config.frameDurationSeconds)
                let processedSec = Double(diarizer.timeline.numFrames) * frameDur
                if eou.endSec > processedSec + 0.5 {
                    stillPending.append(eou)
                    continue
                }
            }
            emitEou(eou, diarizer: diarizer)
        }

        if !stillPending.isEmpty {
            pendingLock.lock()
            pendingEous = stillPending + pendingEous
            pendingLock.unlock()
        }
    }

    private static func emitEou(_ eou: PendingEou, diarizer: SortformerDiarizer?) {
        var payload: [String: Any] = [
            "type": "eou",
            "text": eou.text,
            "audio_sec": eou.endSec,
            "start_sec": eou.startSec,
            "wall_ms": eou.wallMs
        ]
        if let diarizer = diarizer {
            let speaker = dominantSpeaker(diarizer: diarizer, startSec: eou.startSec, endSec: eou.endSec)
            if let speaker = speaker { payload["speaker"] = speaker }
            if diarDebugEnabled { logDiarDebug(diarizer: diarizer, eou: eou, speaker: speaker) }
        }
        emitStatic(payload)
    }

    private static func logDiarDebug(diarizer: SortformerDiarizer, eou: PendingEou, speaker: Int?) {
        let timeline = diarizer.timeline
        var finalized = 0
        var tentative = 0
        for (_, sp) in timeline.speakers {
            finalized += sp.finalizedSegments.count
            tentative += sp.tentativeSegments.count
        }
        let line = "diar [\(String(format: "%.1f", eou.startSec))-\(String(format: "%.1f", eou.endSec))]" +
                   " frames=\(timeline.numFrames) speakers=\(timeline.speakers.count)" +
                   " finalSegs=\(finalized) tentSegs=\(tentative)" +
                   " -> \(speaker.map(String.init) ?? "nil")\n"
        FileHandle.standardError.write(Data(line.utf8))
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
