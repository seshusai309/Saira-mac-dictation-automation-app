import AppKit
import Carbon.HIToolbox
import Foundation

/// The dictation shortcut.
///
/// Two shapes, handled differently by `HotkeyMonitor`:
/// - **A chord** (⌥ Space): a modifier plus a real key, seen as `keyDown` / `keyUp`.
/// - **A lone modifier** (Right ⌥, fn, Right ⌘): seen only as `flagsChanged`.
enum Shortcut: String, CaseIterable, Sendable {
    case optionSpace
    case rightOption
    case fn
    case rightCommand

    var displayName: String {
        keycaps.joined(separator: " ")
    }

    /// Each physical key, for drawing as keycaps.
    var keycaps: [String] {
        switch self {
        case .optionSpace: ["⌥", "Space"]
        case .rightOption: ["Right ⌥"]
        case .fn: ["fn"]
        case .rightCommand: ["Right ⌘"]
        }
    }

    var detail: String {
        switch self {
        case .optionSpace: "Option + Space. Nothing else on a stock Mac uses it."
        case .rightOption: "The right Option key on its own."
        case .fn: "Long-press fn / Globe to dictate. A quick tap still does nothing, so fn+keys keep working."
        case .rightCommand: "The right Command key on its own."
        }
    }

    /// Key code of the modifier, for the lone-modifier shortcuts.
    fileprivate var modifierKeyCode: Int64? {
        switch self {
        case .optionSpace: nil
        case .rightOption: Int64(kVK_RightOption)   // 61
        case .fn: Int64(kVK_Function)               // 63
        case .rightCommand: Int64(kVK_RightCommand) // 54
        }
    }

    /// Device-*dependent* bit for this specific physical key.
    ///
    /// `CGEventFlags.maskAlternate` is the union mask — it's set whenever *either* Option
    /// key is down. Using it means: hold Left ⌥, tap Right ⌥, and the release is invisible
    /// (the union bit is still set by the left key), so the release never fires. The mic
    /// stays open, the pill stays up, and the next press is swallowed too.
    ///
    /// These raw values are the NX_DEVICE* masks from IOKit's event system; they carry the
    /// left/right distinction that the public `CGEventFlags` constants discard.
    fileprivate var modifierFlag: CGEventFlags {
        switch self {
        case .optionSpace: .maskAlternate
        case .rightOption: CGEventFlags(rawValue: 0x40)   // NX_DEVICERALTKEYMASK
        case .rightCommand: CGEventFlags(rawValue: 0x10)  // NX_DEVICERCMDKEYMASK
        case .fn: .maskSecondaryFn                        // no left/right variant exists
        }
    }

    /// Swallowing `fn` would break fn+arrow, fn+delete and the emoji picker, so it's let
    /// through. Dedicated right-hand modifiers are safe to consume.
    fileprivate var consumesModifierEvent: Bool { self != .fn }
}

/// Watches for the shortcut using a `CGEventTap`.
///
/// A tap is required rather than `NSEvent.addGlobalMonitor` for two reasons: `fn` and
/// left/right modifier discrimination don't surface through the higher-level APIs, and only
/// a tap can *swallow* an event — without that, ⌥ Space would also type a non-breaking space
/// into whatever has focus. This needs Accessibility permission; without it `tapCreate`
/// returns nil.
@MainActor
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Lone modifier: whether it's currently down.
    private var modifierDown = false
    /// Chord: `onDown` has fired and `onUp` hasn't yet.
    private var chordActive = false
    /// Chord: Space is physically down. Tracked apart from `chordActive` so that letting go
    /// of ⌥ first still swallows Space's auto-repeat and its eventual key-up — otherwise a
    /// held Space would start typing spaces the instant ⌥ came up.
    private var spaceHeld = false

    /// When the tap last saw any key event. A rebuild logs how long ago that was, which is
    /// how a deaf-but-enabled tap shows up in the log.
    private(set) var lastEventAt: Date?

    var shortcut: Shortcut = .optionSpace
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    /// Esc. Return `true` to swallow it — only while dictating, so Esc keeps working
    /// everywhere else.
    var onEscape: (() -> Bool)?
    /// Some other key went down while a lone-modifier shortcut was held — fn+arrow and the
    /// like. Never swallowed; the controller uses it to tell a key combo from dictation.
    var onInterrupt: (() -> Void)?

    /// - Returns: `false` if the tap couldn't be created — almost always missing Accessibility permission.
    @discardableResult
    func start() -> Bool {
        stop()

        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // CGEvent isn't Sendable, so pull out the plain values before crossing into
                // actor-isolated code. The tap was added to the main run loop, so this
                // callback genuinely does run on the main thread.
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                let consume = MainActor.assumeIsolated {
                    monitor.handle(type: type, keyCode: keyCode, flags: flags)
                }
                return consume ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.hotkey.error("tapCreate failed — Accessibility permission missing?")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.hotkey.info("listening for \(self.shortcut.displayName, privacy: .public)")
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        modifierDown = false
        chordActive = false
        spaceHeld = false
    }

    // MARK: - Staying alive

    /// The watchdog's check. macOS switches a tap off after a stall (and while the Mac sleeps),
    /// and nothing tells the app except an event that may never come — so re-enable it here.
    ///
    /// - Returns: `false` if there's no working tap at all, and it has to be created again.
    func ensureAlive() -> Bool {
        guard let tap, CFMachPortIsValid(tap) else { return false }
        if !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            Log.hotkey.notice("tap found switched off — switched back on")
            resyncAfterGap()
        }
        return true
    }

    /// While the tap was off, a key-up could have gone by unseen, leaving a hold "stuck" on.
    /// Compare what we believe is held with the keyboard's real state and send the release.
    private func resyncAfterGap() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        if shortcut.modifierKeyCode != nil, modifierDown, !flags.contains(shortcut.modifierFlag) {
            modifierDown = false
            onUp?()
        }
        let spaceDown = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Space))
        if chordActive, !spaceDown || !flags.contains(.maskAlternate) {
            chordActive = false
            spaceHeld = spaceDown
            onUp?()
        }
    }

    // MARK: - Tap callback

    /// - Returns: `true` if the event should be swallowed rather than passed along.
    private func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        // The system disables a tap that runs too slowly or is interrupted; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.hotkey.notice("tap switched off by macOS (\(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public)) — switched back on")
            resyncAfterGap()
            return false
        }

        lastEventAt = Date()
        switch type {
        case .keyDown where keyCode == Int64(kVK_Escape):
            return onEscape?() ?? false
        case .keyDown where shortcut.modifierKeyCode != nil && modifierDown:
            onInterrupt?()
            return false
        case .keyDown, .keyUp, .flagsChanged:
            return shortcut.modifierKeyCode == nil
                ? handleChord(type: type, keyCode: keyCode, flags: flags)
                : handleModifier(type: type, keyCode: keyCode, flags: flags)
        default:
            return false
        }
    }

    private func handleChord(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        let isSpace = keyCode == Int64(kVK_Space)

        switch type {
        case .keyDown where isSpace:
            // Auto-repeat, or Space still down after ⌥ was let go: keep swallowing.
            if spaceHeld { return true }

            // Exactly ⌥ — so ⌥⇧Space, ⌃⌥Space and friends stay free for other apps.
            let modifiers = flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
            guard modifiers == .maskAlternate else { return false }

            spaceHeld = true
            chordActive = true
            Log.hotkey.notice("\(self.shortcut.displayName, privacy: .public) down")
            onDown?()
            return true

        case .keyUp where isSpace:
            guard spaceHeld else { return false }
            spaceHeld = false
            if chordActive {
                chordActive = false
                onUp?()
            }
            return true

        case .flagsChanged:
            // Letting go of ⌥ before Space also ends a hold. Never swallowed — the target
            // app has to see ⌥ come up or it'll believe it's still held.
            if chordActive, !flags.contains(.maskAlternate) {
                chordActive = false
                onUp?()
            }
            return false

        default:
            return false
        }
    }

    private func handleModifier(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard type == .flagsChanged, keyCode == shortcut.modifierKeyCode else { return false }

        let nowDown = flags.contains(shortcut.modifierFlag)
        guard nowDown != modifierDown else { return false }
        modifierDown = nowDown

        // Notice level: macOS keeps these in its log, unlike info — so a "stuck" report can be
        // read back afterwards: did the press arrive at all?
        Log.hotkey.notice("\(self.shortcut.displayName, privacy: .public) \(nowDown ? "down" : "up", privacy: .public)")
        if nowDown { onDown?() } else { onUp?() }

        return shortcut.consumesModifierEvent
    }
}
