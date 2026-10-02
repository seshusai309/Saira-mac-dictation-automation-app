import AppKit
import Foundation

/// Saira's own start and finish sounds — soft, warm, and quiet, made in code.
///
/// macOS's "Tink" and "Pop" are bright and clicky; heard dozens of times a day they grate.
/// These are pure tones with a slow fade-in (no click at the start), a natural exponential
/// fade-out, a touch of second harmonic for warmth, in the low-to-mid range where the ear is
/// least sensitive to harshness, and at a low volume. Nothing to ship or license: the WAV
/// bytes are synthesised once at launch.
@MainActor
enum SoftSounds {
    /// "I'm listening": two soft notes rising a major third, C5 → E5.
    private static let start = make(
        notes: [Note(frequency: 523.25, delay: 0), Note(frequency: 659.25, delay: 0.07)],
        length: 0.42,
        decay: 0.11,
        volume: 0.20
    )

    /// "Got it": one low, rounded note that settles — G4.
    private static let done = make(
        notes: [Note(frequency: 392.00, delay: 0)],
        length: 0.32,
        decay: 0.08,
        volume: 0.17
    )

    static func playStart() { play(start) }
    static func playDone() { play(done) }

    private static func play(_ sound: NSSound?) {
        guard let sound else { return }
        sound.stop()     // a rapid re-press restarts it rather than stacking a second copy
        sound.play()
    }

    private struct Note {
        let frequency: Double
        /// Seconds after the sound starts.
        let delay: Double
    }

    /// Renders the notes to a 16-bit mono WAV in memory.
    private static func make(notes: [Note], length: Double, decay: Double, volume: Double) -> NSSound? {
        let sampleRate = 44_100.0
        let frames = Int(length * sampleRate)
        let attack = 0.015                      // fade in: no click
        var samples = [Double](repeating: 0, count: frames)

        for note in notes {
            let start = Int(note.delay * sampleRate)
            for frame in start..<frames {
                let t = Double(frame - start) / sampleRate
                let envelope = min(1, t / attack) * exp(-t / decay)
                let tone = sin(2 * .pi * note.frequency * t)
                    + 0.12 * sin(2 * .pi * note.frequency * 2 * t)   // a little warmth
                samples[frame] += tone * envelope
            }
        }

        // Normalise to the requested volume, then fade the very end to silence.
        let peak = samples.map(abs).max() ?? 1
        let tailStart = Int(Double(frames) * 0.85)
        var pcm = Data(capacity: frames * 2)
        for (frame, sample) in samples.enumerated() {
            let tail = frame < tailStart ? 1 : Double(frames - frame) / Double(frames - tailStart)
            let value = Int16(max(-1, min(1, sample / peak * volume * tail)) * Double(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }
        return NSSound(data: wav(pcm: pcm, sampleRate: Int(sampleRate)))
    }

    private static func wav(pcm: Data, sampleRate: Int) -> Data {
        func le<T: FixedWidthInteger>(_ value: T) -> Data {
            withUnsafeBytes(of: value.littleEndian) { Data($0) }
        }
        var data = Data("RIFF".utf8)
        data += le(UInt32(36 + pcm.count))
        data += Data("WAVEfmt ".utf8)
        data += le(UInt32(16)) + le(UInt16(1)) + le(UInt16(1))          // PCM, mono
        data += le(UInt32(sampleRate)) + le(UInt32(sampleRate * 2))      // byte rate
        data += le(UInt16(2)) + le(UInt16(16))                           // block align, bits
        data += Data("data".utf8) + le(UInt32(pcm.count)) + pcm
        return data
    }
}
