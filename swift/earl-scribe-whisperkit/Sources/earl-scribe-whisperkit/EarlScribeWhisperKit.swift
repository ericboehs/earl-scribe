import Foundation
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
        ) { _, newState in
            EarlScribeWhisperKit.emitState(newState, startedAt: started)
        }

        Self.emit(["type": "start", "started_at": ISO8601DateFormatter().string(from: started)])

        try await transcriber.startStreamTranscription()
    }

    static func emitState(_ state: AudioStreamTranscriber.State, startedAt: Date) {
        for seg in state.confirmedSegments {
            Self.emit([
                "type": "confirmed",
                "text": seg.text,
                "start_sec": seg.start,
                "end_sec": seg.end
            ])
        }
        for seg in state.unconfirmedSegments {
            Self.emit([
                "type": "unconfirmed",
                "text": seg.text,
                "start_sec": seg.start,
                "end_sec": seg.end
            ])
        }
        if !state.currentText.isEmpty {
            Self.emit(["type": "partial", "text": state.currentText])
        }
    }

    static func emit(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes]),
              let line = String(data: data, encoding: .utf8) else { return }
        print(line)
    }
}

