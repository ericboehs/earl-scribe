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
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try? handle.write(contentsOf: data)
        samplesWritten &+= UInt32(samples.count)
    }

    /// Patch RIFF + data chunk sizes, fsync to disk, then close. The fsync
    /// guarantees the rerun subprocess sees the complete file — without it the
    /// patched header can race ahead of the audio bytes still in OS buffers.
    func close() {
        lock.lock(); defer { lock.unlock() }
        let dataBytes = samplesWritten * 4 // Float32
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
        header.append(u16le(3))                              // format: IEEE float
        header.append(u16le(1))                              // channels
        header.append(u32le(sampleRate))
        header.append(u32le(sampleRate * 4))                 // byte rate
        header.append(u16le(4))                              // block align (1ch * 4B)
        header.append(u16le(32))                             // bits per sample
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
