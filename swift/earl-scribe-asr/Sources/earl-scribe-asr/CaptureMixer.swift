import Foundation

/// Mixes mic + system 16 kHz mono Float32 streams into a single mono stream
/// that the ASR/diarizer consumes. Tracks per-channel energy in 100 ms buckets
/// keyed by mixed-stream audio time so EOU events can be tagged with a
/// "mic"/"system" hint based on which channel dominated the segment.
///
/// The mixer is a sample-level zipper: producers append samples to per-source
/// queues; the consumer pulls the *minimum* available count from both queues,
/// sums them (clamped), and emits as a single mono slice. If one channel runs
/// dry, the consumer waits — there's no silence padding, so transient
/// asymmetries don't shift the audio clock.
final class CaptureMixer: @unchecked Sendable {
    private let lock = NSLock()
    private var micQueue: [Float] = []
    private var sysQueue: [Float] = []

    /// Total mixed samples emitted so far (16 kHz mono).
    private var totalEmitted: Int = 0

    /// Per-100ms energy buckets indexed by audio second of bucket start.
    /// One pair per bucket: (mic energy, system energy). Keeping these in
    /// parallel arrays keeps lookup O(window-size) for EOU tagging.
    private var bucketStartSec: [Double] = []
    private var bucketMicEnergy: [Float] = []
    private var bucketSysEnergy: [Float] = []

    private let sampleRate: Double = 16_000
    private let bucketSamples: Int = 1_600 // 100 ms

    /// Pending energy accumulator for the in-progress bucket.
    private var pendingBucketSamples: Int = 0
    private var pendingMicE: Float = 0
    private var pendingSysE: Float = 0

    func ingestMic(_ samples: [Float]) {
        lock.lock(); micQueue.append(contentsOf: samples); lock.unlock()
    }

    func ingestSys(_ samples: [Float]) {
        lock.lock(); sysQueue.append(contentsOf: samples); lock.unlock()
    }

    /// Pull and emit as many fully-paired samples as possible. Returns the
    /// mixed slice (may be empty). Updates the energy bucket index as a
    /// side effect.
    func pullMixed() -> [Float] {
        lock.lock()
        let n = min(micQueue.count, sysQueue.count)
        if n == 0 { lock.unlock(); return [] }
        let mic = Array(micQueue.prefix(n))
        let sys = Array(sysQueue.prefix(n))
        micQueue.removeFirst(n)
        sysQueue.removeFirst(n)
        var mixed = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var v = mic[i] + sys[i]
            if v > 1.0 { v = 1.0 } else if v < -1.0 { v = -1.0 }
            mixed[i] = v
        }
        accumulateEnergy(mic: mic, sys: sys)
        totalEmitted += n
        lock.unlock()
        return mixed
    }

    /// Returns "mic" if mic energy dominated [startSec, endSec], "system" otherwise.
    /// Returns nil if no buckets cover the window (e.g., before any audio).
    func channelHint(startSec: Double, endSec: Double) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard !bucketStartSec.isEmpty, endSec > startSec else { return nil }
        var micTotal: Float = 0
        var sysTotal: Float = 0
        for i in 0..<bucketStartSec.count {
            let t = bucketStartSec[i]
            if t >= endSec { break }
            if t + 0.1 <= startSec { continue }
            micTotal += bucketMicEnergy[i]
            sysTotal += bucketSysEnergy[i]
        }
        if micTotal == 0 && sysTotal == 0 { return nil }
        return micTotal > sysTotal ? "mic" : "system"
    }

    /// Caller must hold lock.
    private func accumulateEnergy(mic: [Float], sys: [Float]) {
        let n = mic.count
        var i = 0
        while i < n {
            let take = min(bucketSamples - pendingBucketSamples, n - i)
            var me: Float = 0
            var se: Float = 0
            for j in 0..<take {
                let m = mic[i + j]
                let s = sys[i + j]
                me += m * m
                se += s * s
            }
            pendingMicE += me
            pendingSysE += se
            pendingBucketSamples += take
            i += take
            if pendingBucketSamples >= bucketSamples {
                let bucketIdx = bucketStartSec.count
                bucketStartSec.append(Double(bucketIdx) * 0.1)
                bucketMicEnergy.append(pendingMicE)
                bucketSysEnergy.append(pendingSysE)
                pendingBucketSamples = 0
                pendingMicE = 0
                pendingSysE = 0
            }
        }
    }
}
