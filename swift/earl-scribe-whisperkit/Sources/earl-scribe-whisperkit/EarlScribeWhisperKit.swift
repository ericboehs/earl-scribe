import Foundation
import Darwin
import ArgumentParser
import WhisperKit

@main
struct EarlScribeWhisperKit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "earl-scribe-whisperkit",
        abstract: "Streaming WhisperKit shim — reads Float32 16k mono PCM from stdin, emits JSONL events."
    )

    @Option(help: "Path to a WhisperKit model folder (containing AudioEncoder.mlmodelc, etc.).")
    var modelPath: String

    @Option(help: "Required confirmed-segment count before emitting (default 2).")
    var confirmCount: Int = 2

    @Option(help: "Silence threshold for VAD (default 0.3).")
    var silenceThreshold: Float = 0.3

    @Flag(help: "Enable VAD-based segment confirmation.")
    var vad: Bool = false

    func run() async throws {
        Self.emit(["type": "info", "msg": "loading_models", "path": modelPath])

        let config = WhisperKitConfig(
            modelFolder: modelPath,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        let whisperKit = try await WhisperKit(config)
        guard let tokenizer = whisperKit.tokenizer else {
            Self.emit(["type": "error", "msg": "tokenizer unavailable"])
            return
        }

        let audio = StdinAudioProcessor()
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = "en"
        options.wordTimestamps = true
        options.skipSpecialTokens = true

        Self.emit(["type": "models_loaded"])

        let started = Date()
        let transcriber = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: audio,
            decodingOptions: options,
            requiredSegmentsForConfirmation: confirmCount,
            silenceThreshold: silenceThreshold,
            useVAD: vad
        ) { oldState, newState in
            EarlScribeWhisperKit.emitState(oldState: oldState, newState: newState)
        }

        Self.emit(["type": "start", "started_at": ISO8601DateFormatter().string(from: started)])

        // After stdin EOF, give the transcriber a few seconds to drain the
        // remaining buffer, then exit the process. AudioStreamTranscriber has
        // no public "stop after current buffer" hook; this is the simplest
        // shutdown that doesn't truncate the trailing segments.
        Task { @Sendable [audio] in
            while !audio.eofReached {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            Self.emit(["type": "stopped"])
            Darwin.exit(0)
        }

        try await transcriber.startStreamTranscription()
    }

    static func emitState(oldState: AudioStreamTranscriber.State,
                          newState: AudioStreamTranscriber.State) {
        let alreadyConfirmed = oldState.confirmedSegments.count
        for seg in newState.confirmedSegments.dropFirst(alreadyConfirmed) {
            Self.emit([
                "type": "confirmed",
                "text": seg.text,
                "start_sec": seg.start,
                "end_sec": seg.end
            ])
        }
        if newState.currentText != oldState.currentText, !newState.currentText.isEmpty {
            Self.emit(["type": "partial", "text": newState.currentText])
        }
    }

    static func emit(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
    }
}

