import SairaDictionary
import AVFoundation
import AppKit
import Foundation
import Observation

/// Builds the speech engine for the current language setting.
///
/// Apple's `SpeechTranscriber` only. Parakeet was tried and removed: on this Mac it peaked at
/// ~600 MB in-process and kept ~460 MB on disk, against Apple's model which lives in a small
/// system service and costs the app next to nothing — for a difference in speed and accuracy
/// the user couldn't feel. Read per-utterance, so a language change applies immediately.
@MainActor
func engineForCurrentSettings() -> any TranscriptionEngine {
    let identifier = Settings.shared.languageIdentifier
    return AppleSpeechEngine(locale: identifier.isEmpty ? .current : Locale(identifier: identifier))
}

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            case .idle, .error: false
            }
        }
    }

    /// Where a dictation was started from, which decides where its text goes.
    enum Source {
        /// The keyboard shortcut, from inside any app — the text is typed there.
        case shortcut
        /// A click on the flow pill. The pill never takes focus, so this too types into
        /// whatever app is in front.
        case pill
        /// The Dictate screen in the app's own window. There's no foreign text field to type
        /// into, so the result waits on the result card for Copy or Insert.
        case window
    }

    /// A brief note on the pill after the text lands — only when there's something to *do*.
    ///
    /// Typed text gets no confirmation at all: the words appearing at the cursor is the
    /// confirmation, and a popup after them is just in the way. The one case worth a note is
    /// copy-only, where nothing appears until you paste.
    enum Delivery: Equatable {
        case copied
    }

    private(set) var state: State = .idle
    /// Live transcript, updated as the engine revises it.
    private(set) var transcript = ""
    /// Smoothed 0…1 mic level for the waveforms.
    private(set) var level: Float = 0
    /// When the current recording began. Drives the elapsed counter.
    private(set) var recordingStartedAt: Date?
    /// `true` when recording keeps going without a key held — toggle mode, the pill, or the
    /// window. The pill shows stop and cancel buttons only then.
    private(set) var isHandsFree = false
    /// `true` once a dictation is deliberate: a hold that's lasted `holdThreshold`, or any
    /// hands-free start. Until then nothing is shown or played, and letting go throws the
    /// recording away — so a quick tap of fn is still just a tap of fn.
    private(set) var isEngaged = false
    /// Whether the keyboard shortcut is live. False until Accessibility is granted.
    private(set) var isShortcutArmed = false
    /// The app currently holding macOS *Secure Event Input*, if any. While any app holds it,
    /// macOS hides every key press from every key listener on the Mac — Saira's included —
    /// so the shortcut can't work until that app lets go. Shown in the UI so it's not a mystery.
    private(set) var secureInputHolder: String?
    private(set) var source: Source = .shortcut
    /// The most recent dictation — or a past one picked from history — for the result card.
    private(set) var lastResult: DictationRun?
    /// Set for a moment after text lands, so the pill can show a check.
    private(set) var delivery: Delivery?

    private let hotkey = HotkeyMonitor()
    private let capture = AudioCapture()
    private let makeEngine: @MainActor () -> any TranscriptionEngine

    /// Injected only by tests; production picks a formatter per utterance below.
    private let formatter: (any TextFormatter)?

    private var engine: (any TranscriptionEngine)?
    private var consumeTask: Task<Void, Never>?
    private var feedTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    /// When the key was let go — the recording's end, so the pill's timer can freeze there.
    private(set) var releasedAt: Date?
    private var engineName = ""
    /// Bumped per dictation so a stale "clear the check" timer can't hide a newer one.
    private var deliveryGeneration = 0
    /// Bumped per dictation so a stale hold timer can't engage a newer one.
    private var dictationGeneration = 0

    /// How long the shortcut must be held before it counts as dictation. Long enough that a
    /// tap of fn (emoji, fn+arrow) never starts anything; short enough not to feel slow.
    /// Audio is captured from the first instant, so nothing said in this window is lost.
    static let holdThreshold: Duration = .milliseconds(300)

    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @MainActor () -> any TranscriptionEngine = engineForCurrentSettings
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine
    }

    /// Chosen per utterance so Settings and the template apply to the very next dictation.
    private func activeFormatter(for template: DictationTemplate) -> any TextFormatter {
        if let formatter { return formatter }
        return Settings.shared.smartCleanup
            ? FoundationModelFormatter(template: template)
            : RuleBasedFormatter(template: template)
    }

    // MARK: - Lifecycle

    /// - Returns: `false` if the hotkey tap couldn't be installed (missing Accessibility).
    @discardableResult
    func activate() -> Bool {
        hotkey.shortcut = Settings.shared.shortcut
        hotkey.onDown = { [weak self] in self?.shortcutDown() }
        hotkey.onUp = { [weak self] in self?.shortcutUp() }
        hotkey.onEscape = { [weak self] in self?.cancel() ?? false }
        hotkey.onInterrupt = { [weak self] in self?.shortcutInterrupted() }
        isShortcutArmed = hotkey.start()
        return isShortcutArmed
    }

    func deactivate() {
        hotkey.stop()
        cancelDictation()
    }

    /// The watchdog's check, every couple of seconds and on wake: keeps the shortcut working
    /// no matter how long the app has sat in the background.
    ///
    /// Re-enables a tap macOS switched off; recreates one that's gone (a grant that came back,
    /// or was given for the first time); and keeps `isShortcutArmed` honest either way.
    func keepShortcutAlive() {
        if hotkey.ensureAlive() {
            if !isShortcutArmed { isShortcutArmed = true }
            return
        }
        if isShortcutArmed {
            isShortcutArmed = false
            Log.hotkey.error("shortcut lost — re-arming")
        }
        guard Permissions.hasAccessibility else { return }
        if activate() { Log.hotkey.info("shortcut armed") }
    }

    /// Throws the key listener away and makes a fresh one — the same effect as restarting the
    /// app. A listener can stay "enabled" and still stop hearing keys (after sleep, after
    /// Secure Input); re-enabling doesn't fix that, recreating does. Skipped mid-dictation.
    func rebuildShortcut(reason: String) {
        guard !state.isActive, Permissions.hasAccessibility else { return }
        let silence = hotkey.lastEventAt.map { Int(Date().timeIntervalSince($0)) }
        if activate() {
            Log.hotkey.info("""
                shortcut rebuilt (\(reason, privacy: .public)) — last key event \(silence.map { "\($0)s" } ?? "never", privacy: .public) ago
                """)
        }
    }

    /// The watchdog's Secure Input check. Rebuilds the listener the moment the holder lets go.
    func updateSecureInput(holder: String?) {
        guard holder != secureInputHolder else { return }
        let ended = secureInputHolder != nil && holder == nil
        secureInputHolder = holder
        if let holder {
            Log.hotkey.info("Secure Input held by \(holder, privacy: .public) — keys are hidden from Saira")
        } else if ended {
            rebuildShortcut(reason: "Secure Input ended")
        }
    }

    /// Re-arms the tap after the user picks a different shortcut.
    @discardableResult
    func reloadHotkey() -> Bool {
        hotkey.stop()
        return activate()
    }

    // MARK: - Starting and stopping

    private func shortcutDown() {
        switch Settings.shared.activationMode {
        case .hold:
            beginDictation(from: .shortcut, handsFree: false)
        case .toggle:
            if state.isActive {
                endDictation()
            } else {
                beginDictation(from: .shortcut, handsFree: true)
            }
        }
    }

    private func shortcutUp() {
        // A hands-free recording (toggle mode, or started from the pill or window) ignores
        // key-ups — it ends on the next press, or the stop button.
        guard !isHandsFree else { return }
        if isEngaged {
            endDictation()
        } else {
            // Let go before the threshold: a tap, not a dictation. Nothing to transcribe.
            cancelDictation()
        }
    }

    /// Another key went down while the shortcut's modifier was held — fn+arrow, fn+Delete.
    /// That's a keyboard shortcut, not dictation, so drop a hold that hasn't engaged yet.
    private func shortcutInterrupted() {
        guard state.isActive, !isEngaged, !isHandsFree else { return }
        cancelDictation()
    }

    /// The moment a dictation becomes deliberate: the pill appears and the start sound plays.
    private func engage() {
        guard !isEngaged else { return }
        isEngaged = true
        if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }
    }

    /// Record / stop from the flow pill.
    func togglePill() {
        if state.isActive { endDictation() } else { beginDictation(from: .pill, handsFree: true) }
    }

    /// Record / stop from the Dictate screen.
    func toggleFromWindow() {
        if state.isActive { endDictation() } else { beginDictation(from: .window, handsFree: true) }
    }

    func stop() {
        endDictation()
    }

    /// Throws the current recording away. Esc, or ✕ on the pill.
    ///
    /// - Returns: `true` if there was something to cancel — so Esc is only swallowed while
    ///   dictating and keeps working everywhere else.
    @discardableResult
    func cancel() -> Bool {
        guard state.isActive else { return false }
        Log.app.info("dictation cancelled")
        cancelDictation()
        return true
    }

    // MARK: - The result card

    /// Shows a past dictation on the result card.
    func show(_ run: DictationRun) {
        lastResult = run
    }

    func clearResult() {
        lastResult = nil
    }

    /// Saves an edit made on the result card back into history.
    func updateResultText(_ text: String) {
        guard var run = lastResult, run.text != text else { return }
        run.text = text
        lastResult = run
        RunLog.update(run)
    }

    func copyResult() {
        guard let text = lastResult?.text else { return }
        TextInjector.copy(text)
    }

    /// Types the result into the app you were in before this window.
    func insertResult() {
        guard let text = lastResult?.text else { return }
        TextInjector.insertIntoPreviousApp(text, keepOnClipboard: Settings.shared.autoCopy)
    }

    // MARK: - Dictation

    private func beginDictation(from source: Source, handsFree: Bool) {
        guard !state.isActive else { return }
        state = .starting
        transcript = ""
        delivery = nil
        self.source = source
        isHandsFree = handsFree
        recordingStartedAt = Date()
        releasedAt = nil
        engineName = "Apple"
        let microphoneUID = Settings.shared.microphoneUID

        isEngaged = false
        dictationGeneration += 1
        if Settings.shared.cleanupEnabled, Settings.shared.smartCleanup {
            FoundationModelFormatter.prewarm(template: Settings.shared.template)
        }
        if handsFree {
            engage()
        } else {
            let generation = dictationGeneration
            Task { @MainActor in
                try? await Task.sleep(for: Self.holdThreshold)
                guard generation == dictationGeneration, state.isActive else { return }
                engage()
            }
        }

        Task { @MainActor in
            do {
                guard await Permissions.requestMicrophone() else {
                    fail("Microphone access is off. Turn it on in System Settings ▸ Privacy & Security ▸ Microphone.")
                    return
                }

                let engine = makeEngine()
                self.engine = engine

                let chunks = try await engine.start()

                guard let format = await engine.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }

                // Audio must reach the engine in capture order. A stream plus a single
                // draining task guarantees that; spawning a Task per buffer would not.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation

                self.feedTask = Task.detached(priority: .userInitiated) {
                    for await chunk in audioStream {
                        await engine.feed(chunk)
                    }
                }

                try capture.start(
                    outputFormat: format,
                    microphoneUID: microphoneUID,
                    onBuffer: { chunk in
                        audioContinuation.yield(chunk)
                    },
                    // A strong capture is fine: the controller lives as long as the app.
                    onLevel: { level in
                        Task { @MainActor in self.updateLevel(level) }
                    }
                )

                // Bail out if the user already let go while we were spinning up.
                guard case .starting = self.state else {
                    await self.teardown()
                    return
                }

                self.state = .listening

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            self.transcript = chunk.text
                        }
                    } catch {
                        self.fail(error.localizedDescription)
                    }
                }
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func endDictation() {
        // `.finishing` is "active", so without this a second press during processing would
        // run the whole tail again — re-reading `transcript` before the first pass cleared
        // it and pasting the same utterance twice. The window is widest with smart cleanup,
        // which can add up to 2.5s.
        guard state.isActive, state != .finishing else { return }
        state = .finishing
        capture.stop()
        level = 0
        releasedAt = Date()

        Task { @MainActor in
            // Drain every captured buffer into the engine before asking it to finalize,
            // or the tail of the utterance gets dropped.
            audioContinuation?.finish()
            audioContinuation = nil
            await feedTask?.value
            feedTask = nil

            let clock = ContinuousClock()
            let released = clock.now
            await engine?.finish()
            await consumeTask?.value
            consumeTask = nil
            engine = nil
            let transcribed = clock.now

            let raw = transcript
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finishQuietly()
                return
            }

            let template = Settings.shared.template
            let cleaned = Settings.shared.cleanupEnabled
                ? await activeFormatter(for: template).format(raw)
                : raw

            // The dictionary runs last, and runs regardless of the cleanup setting. Biasing
            // only raises the odds of the right word; this is the pass that guarantees it,
            // so it must not be something the user can accidentally switch off.
            let cleanedAt = clock.now
            let (output, corrections) = DictionaryStore.shared.corrector.apply(to: cleaned)
            if !corrections.isEmpty {
                Log.speech.info("dictionary · \(corrections.count, privacy: .public) correction(s) applied")
            }

            let run = recordRun(text: output, corrections: corrections, template: template)
            lastResult = run
            deliver(output)

            // Where the wait went, per stage — the first thing to read when it feels slow.
            let transcribe = transcribed - released
            let cleanup = cleanedAt - transcribed
            let total = clock.now - released
            Log.speech.info("""
                timing · transcribe \(transcribe, privacy: .public) · cleanup \(cleanup, privacy: .public) · \
                total \(total, privacy: .public)
                """)

            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }
            state = .idle
            transcript = ""
            recordingStartedAt = nil
            isEngaged = false
        }
    }

    /// Sends the finished text where it belongs for how the dictation was started.
    private func deliver(_ text: String) {
        let settings = Settings.shared
        switch source {
        case .window:
            // The result card on the Dictate screen shows it — no popup needed.
            if settings.autoCopy { TextInjector.copy(text) }
        case .shortcut, .pill:
            if settings.insertAtCursor {
                TextInjector.insert(text, keepOnClipboard: settings.autoCopy)
            } else {
                // With insertion off the clipboard is the only way out, whatever Auto-copy
                // says — otherwise the words would land nowhere but history.
                TextInjector.copy(text)
                flash(.copied)
            }
        }
    }

    private func flash(_ kind: Delivery) {
        deliveryGeneration += 1
        let generation = deliveryGeneration
        delivery = kind
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if generation == deliveryGeneration { delivery = nil }
        }
    }

    /// Silence, or a stray tap of the key: nothing to type and nothing to file.
    private func finishQuietly() {
        state = .idle
        transcript = ""
        recordingStartedAt = nil
        isEngaged = false
    }

    private func cancelDictation() {
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        let engine = self.engine
        self.engine = nil
        Task { await engine?.finish() }

        state = .idle
        transcript = ""
        level = 0
        recordingStartedAt = nil
        isEngaged = false
        dictationGeneration += 1
    }

    private func teardown() async {
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        await feedTask?.value
        feedTask = nil
        await engine?.finish()
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .idle
        recordingStartedAt = nil
        isEngaged = false
    }

    // MARK: - Helpers

    /// Files the finished utterance in history.
    ///
    /// `processSeconds` is measured from key release, not from capture start — that's the
    /// wait the user actually experiences, and it's the only number on which a streaming
    /// engine and a batch engine can be compared honestly.
    private func recordRun(
        text: String,
        corrections: [AppliedCorrection],
        template: DictationTemplate
    ) -> DictationRun {
        let started = recordingStartedAt ?? Date()
        let released = releasedAt ?? Date()
        let run = DictationRun(
            date: released,
            engine: engineName,
            audioSeconds: released.timeIntervalSince(started),
            processSeconds: Date().timeIntervalSince(released),
            text: text,
            corrections: corrections.isEmpty ? nil : corrections,
            template: template.rawValue
        )
        RunLog.record(run)
        return run
    }

    /// Light smoothing so the waveform glides instead of strobing at buffer rate.
    private func updateLevel(_ new: Float) {
        guard state == .listening || state == .starting else { return }
        level += (new - level) * 0.35
    }

    #if DEBUG
    /// Puts the controller into a state without recording anything — for design snapshots.
    func debugSimulate(_ state: State, transcript: String = "", level: Float = 0, handsFree: Bool = false) {
        self.state = state
        self.transcript = transcript
        self.level = level
        isHandsFree = handsFree
        source = .shortcut
        releasedAt = state == .finishing ? Date() : nil
        isEngaged = state.isActive
        recordingStartedAt = state.isActive ? Date().addingTimeInterval(-7) : nil
    }
    #endif

    private func fail(_ message: String) {
        Log.app.error("\(message)")
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .error(message)
        level = 0
        recordingStartedAt = nil
        isEngaged = false

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = state { state = .idle }
        }
    }
}
