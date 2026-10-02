import Foundation
import Synchronization

/// Recent voice levels, written by the audio thread and read by the pill at display rate.
///
/// Deliberately *not* observable: the old pill bars read an `@Observable` level, so every
/// audio buffer invalidated SwiftUI and re-ran the view tree. Here the audio thread just
/// appends to a ring under a lock (no main-thread hop, no SwiftUI work), and the pill's
/// `Canvas` pulls the latest values once per frame. Smoother bars, less CPU.
final class LevelMeter: Sendable {
    /// How many recent levels are kept — more than any drawing needs.
    static let capacity = 96

    private struct Ring {
        var values = [Float](repeating: 0, count: LevelMeter.capacity)
        var head = 0
    }

    private let ring = Mutex(Ring())

    /// Audio thread: one level per ~10 ms slice of audio, 0…1.
    func push(_ level: Float) {
        ring.withLock { ring in
            ring.values[ring.head] = level
            ring.head = (ring.head + 1) % LevelMeter.capacity
        }
    }

    func reset() {
        ring.withLock { $0 = Ring() }
    }

    /// The newest `count` levels, oldest first.
    func recent(_ count: Int) -> [Float] {
        ring.withLock { ring in
            let n = min(count, LevelMeter.capacity)
            return (0..<n).map { offset in
                ring.values[(ring.head - n + offset + LevelMeter.capacity) % LevelMeter.capacity]
            }
        }
    }

    /// Loudness of a run of samples as 0…1, tuned for speech: about −55 dBFS (room hush) to
    /// −12 dBFS (raised voice). The old −50…0 range left normal talking in the bottom half,
    /// so the bars barely moved.
    static func level(of samples: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            sum += samples[i] * samples[i]
        }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))
        return max(0, min(1, (db + 55) / 43))
    }
}
