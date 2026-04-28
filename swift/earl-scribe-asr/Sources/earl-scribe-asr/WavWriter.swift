import Foundation

/// Streaming 16 kHz mono Float32 WAV writer. Writes a placeholder header up
/// front, appends raw float samples as they arrive, and patches the RIFF/data
/// chunk sizes at close. If the process crashes mid-capture, the file's still
/// readable up to whatever was flushed to disk by the last `write`.
final class WavWriter {
    private let handle: FileHandle
    private let sampleRate: UInt32
    private var samplesWritten: UInt32 = 0
    private let lock = NSLock()
    let path: String

    init(path: String, sampleRate: UInt32 = 16_000) throws {
        self.path = path
        self.sampleRate = sampleRate
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: path) else {
            throw WavWriterError.cannotOpen(path)
        }
        self.handle = fh
        try writePlaceholderHeader()
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var int16Samples = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let v = max(-1.0, min(1.0, samples[i]))
            int16Samples[i] = Int16(v * 32_767.0)
        }
        let data = int16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try? handle.write(contentsOf: data)
        samplesWritten &+= UInt32(samples.count)
    }

    /// Patch RIFF + data chunk sizes, fsync to disk, then close. The fsync
    /// guarantees the rerun subprocess sees the complete file — without it the
    /// patched header can race ahead of the audio bytes still in OS buffers.
    func close() {
        lock.lock(); defer { lock.unlock() }
        let dataBytes = samplesWritten * 2 // Int16
        let riffSize = 36 + dataBytes
        try? handle.seek(toOffset: 4)
        try? handle.write(contentsOf: u32le(riffSize))
        try? handle.seek(toOffset: 40)
        try? handle.write(contentsOf: u32le(dataBytes))
        try? handle.synchronize()
        try? handle.close()
    }

    private func writePlaceholderHeader() throws {
        var header = Data()
        header.append(Data("RIFF".utf8))
        header.append(u32le(0))                              // file size – patched
        header.append(Data("WAVE".utf8))
        header.append(Data("fmt ".utf8))
        header.append(u32le(16))                             // fmt chunk size
        header.append(u16le(1))                              // format: PCM (Int16)
        header.append(u16le(1))                              // channels
        header.append(u32le(sampleRate))
        header.append(u32le(sampleRate * 2))                 // byte rate
        header.append(u16le(2))                              // block align (1ch * 2B)
        header.append(u16le(16))                             // bits per sample
        header.append(Data("data".utf8))
        header.append(u32le(0))                              // data size – patched
        try handle.write(contentsOf: header)
    }

    private func u16le(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 2)
    }

    private func u32le(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: 4)
    }
}

enum WavWriterError: Error, LocalizedError {
    case cannotOpen(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let p): return "cannot open WAV for writing: \(p)"
        }
    }
}
