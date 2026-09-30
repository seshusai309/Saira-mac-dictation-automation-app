import AVFoundation
import AppKit
import ApplicationServices
import Foundation

/// SAI's Whisper needs two grants, and neither can be worked around:
/// - **Microphone** — obviously.
/// - **Accessibility** — for both the `CGEventTap` (hotkey) and the AX text insert.
///
/// Accessibility has no programmatic request; the OS only shows the prompt, and the user
/// must toggle it in System Settings. TCC also keys on the code signature, so re-signing
/// the app resets the grant.
@MainActor
enum Permissions {
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Shows the system Accessibility prompt if the app isn't yet trusted.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        // Spelled out rather than using `kAXTrustedCheckOptionPrompt`, which imports as a
        // mutable global and so isn't usable from concurrency-checked code.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Clears this app's Accessibility row and asks again — the fix for a grant that shows as
    /// on but doesn't work, which happens when the app's signature changed since it was
    /// granted. Scoped to this bundle ID: a bare `tccutil reset Accessibility` would wipe the
    /// grant of every app on the Mac.
    static func resetAndRequestAccessibility() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "ai.sai.whisper"]
        try? process.run()
        process.waitUntilExit()
        promptForAccessibility()
        openAccessibilitySettings()
    }

    /// What the fn / Globe key does on its own, from System Settings ▸ Keyboard: 0 do nothing,
    /// 1 change input source, 2 show emoji, 3 start (Apple's) dictation. Anything but 0 fights
    /// SAI's Whisper for the key.
    static var globeKeyAction: Int {
        UserDefaults(suiteName: "com.apple.HIToolbox")?.integer(forKey: "AppleFnUsageType") ?? 0
    }

    static func openKeyboardSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
}
