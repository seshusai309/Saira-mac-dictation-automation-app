import AppKit
import Foundation
import Observation

/// Hold the shortcut for as long as you talk, or tap it once to start and again to stop.
enum ActivationMode: String, CaseIterable, Sendable {
    case hold
    case toggle
}

enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    var shortcut: Shortcut {
        didSet { defaults.set(shortcut.rawValue, forKey: Keys.shortcut) }
    }

    var activationMode: ActivationMode {
        didSet { defaults.set(activationMode.rawValue, forKey: Keys.activationMode) }
    }

    /// BCP-47 identifier for the speech engine. Empty means "follow the system language".
    var languageIdentifier: String {
        didSet { defaults.set(languageIdentifier, forKey: Keys.languageIdentifier) }
    }

    /// Core Audio UID of the chosen input. Empty means "the system default input". A UID
    /// rather than a device ID because IDs are reassigned on every reconnect.
    var microphoneUID: String {
        didSet { defaults.set(microphoneUID, forKey: Keys.microphoneUID) }
    }

    /// How cleanup shapes the text — see `DictationTemplate`.
    var template: DictationTemplate {
        didSet { defaults.set(template.rawValue, forKey: Keys.template) }
    }

    /// Run the cleanup pass before injecting. Off = raw engine output.
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: Keys.cleanupEnabled) }
    }

    /// Use the on-device LLM for cleanup instead of the deterministic rule pass.
    var smartCleanup: Bool {
        didSet { defaults.set(smartCleanup, forKey: Keys.smartCleanup) }
    }

    /// Leave every finished dictation on the clipboard as well as typing it.
    var autoCopy: Bool {
        didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) }
    }

    /// Type the result where the cursor is. Off = copy only, and paste it yourself.
    var insertAtCursor: Bool {
        didSet { defaults.set(insertAtCursor, forKey: Keys.insertAtCursor) }
    }

    /// Keep a tiny flow pill on screen between dictations. Off by default: the pill appears
    /// when you hold the shortcut, and otherwise stays out of the way.
    var showIdlePill: Bool {
        didSet { defaults.set(showIdlePill, forKey: Keys.showIdlePill) }
    }

    /// Bubbles rising off the pill while you talk. Off by default — the pill alone is the
    /// simple look; this is an extra.
    var voiceBubbles: Bool {
        didSet { defaults.set(voiceBubbles, forKey: Keys.voiceBubbles) }
    }

    /// Play a short sound when capture starts and when text lands.
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.theme)
            applyTheme()
        }
    }

    func applyTheme() {
        NSApp.appearance = theme.appearance
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let shortcut = "shortcut"
        static let activationMode = "activationMode"
        static let languageIdentifier = "languageIdentifier"
        static let microphoneUID = "microphoneUID"
        static let template = "template"
        static let cleanupEnabled = "cleanupEnabled"
        static let smartCleanup = "smartCleanup"
        static let autoCopy = "autoCopy"
        static let insertAtCursor = "insertAtCursor"
        // Renamed when the default flipped to off, so an old stored "on" doesn't linger.
        static let showIdlePill = "showIdlePillWhenIdle"
        static let soundEnabled = "soundEnabled"
        static let voiceBubbles = "voiceBubbles"
        static let theme = "theme"
    }

    private init() {
        // A local, not `self.defaults`: these helpers run before every stored property is
        // initialized, when touching `self` isn't allowed yet.
        let defaults = UserDefaults.standard
        func string(_ key: String) -> String { defaults.string(forKey: key) ?? "" }
        func bool(_ key: String, default value: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? value
        }

        // ⌥ Space by default: two keys nothing else on a stock Mac claims, reachable with
        // either hand, and the same chord the mockup and Wispr Flow's site advertise.
        shortcut = Shortcut(rawValue: string(Keys.shortcut)) ?? .optionSpace
        activationMode = ActivationMode(rawValue: string(Keys.activationMode)) ?? .hold
        languageIdentifier = string(Keys.languageIdentifier)
        microphoneUID = string(Keys.microphoneUID)
        template = DictationTemplate(rawValue: string(Keys.template)) ?? .everyday
        cleanupEnabled = bool(Keys.cleanupEnabled, default: true)
        smartCleanup = bool(Keys.smartCleanup, default: false)
        autoCopy = bool(Keys.autoCopy, default: false)
        insertAtCursor = bool(Keys.insertAtCursor, default: true)
        showIdlePill = bool(Keys.showIdlePill, default: false)
        soundEnabled = bool(Keys.soundEnabled, default: true)
        voiceBubbles = bool(Keys.voiceBubbles, default: false)
        theme = AppTheme(rawValue: string(Keys.theme)) ?? .system
    }
}
