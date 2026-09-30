import AVFoundation
import CoreAudio
import Foundation
import Observation

/// One microphone the Mac can record from.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    /// Core Audio's UID — stable across reconnects, so it's what Settings stores.
    let uid: String
    let name: String
    var id: String { uid }
}

/// Input-device discovery over Core Audio's HAL.
///
/// AVFoundation has no macOS API for "record from *this* microphone" on an `AVAudioEngine`;
/// the device has to be set on the input node's underlying audio unit by `AudioDeviceID`.
/// IDs are reassigned whenever a device reconnects, so the app persists the UID and resolves
/// it here at the moment recording starts.
enum AudioDevices {
    static func inputs() -> [AudioInputDevice] {
        deviceIDs().compactMap { id in
            guard inputChannelCount(of: id) > 0,
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                  let name = stringProperty(kAudioObjectPropertyName, of: id)
            else { return nil }
            return AudioInputDevice(uid: uid, name: name)
        }
    }

    /// Resolves a stored UID to the device's current ID. An empty UID — "System default" —
    /// resolves to whatever the system default input is right now, so choosing it after a
    /// specific device really does switch back.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        if uid.isEmpty { return defaultInputID() }
        return deviceIDs().first { stringProperty(kAudioDevicePropertyDeviceUID, of: $0) == uid }
    }

    static func defaultInputName() -> String? {
        defaultInputID().flatMap { stringProperty(kAudioObjectPropertyName, of: $0) }
    }

    /// Points an engine's input at a device. Must be called before the engine reads its
    /// input format or starts, because switching device changes that format.
    static func select(uid: String, on engine: AVAudioEngine) {
        guard let id = deviceID(forUID: uid) else {
            Log.audio.error("microphone \(uid, privacy: .public) not found — using the current input")
            return
        }
        do {
            try engine.inputNode.auAudioUnit.setDeviceID(id)
        } catch {
            Log.audio.error("couldn't select microphone: \(error.localizedDescription)")
        }
    }

    // MARK: - HAL plumbing

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultInputID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        return status == noErr && id != 0 ? id : nil
    }

    /// Total input channels — zero for output-only devices like speakers.
    private static func inputChannelCount(of id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

/// A short-lived level meter for Settings, so you can check a microphone before dictating.
///
/// Runs its own engine rather than borrowing `AudioCapture`'s, which belongs to dictation and
/// is torn down after every utterance. Only runs while you've asked it to — an open input
/// lights the orange privacy dot, and that should never happen behind your back.
@MainActor
@Observable
final class MicTest {
    private(set) var level: Float = 0
    private(set) var isRunning = false
    private(set) var failure: String?

    private var engine: AVAudioEngine?

    func start(uid: String) async {
        guard !isRunning else { return }
        failure = nil
        guard await Permissions.requestMicrophone() else {
            failure = "Microphone access is off in System Settings."
            return
        }

        let engine = AVAudioEngine()
        AudioDevices.select(uid: uid, on: engine)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Explicitly `@Sendable`: this runs on the real-time audio thread, and a closure
        // formed here would otherwise inherit main-actor isolation and trap when called
        // off the main thread.
        let onLevel: @Sendable (Float) -> Void = { [weak self] value in
            Task { @MainActor in self?.update(value) }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            onLevel(AudioCapture.rms(of: buffer))
        }

        do {
            engine.prepare()
            try engine.start()
            self.engine = engine
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            failure = "Couldn't open the microphone: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        level = 0
    }

    private func update(_ value: Float) {
        guard isRunning else { return }
        level += (value - level) * 0.4
    }
}
