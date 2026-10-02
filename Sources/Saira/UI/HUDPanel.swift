import AppKit
import SwiftUI

/// The window the flow pill lives in.
///
/// The single most important property here is that this panel **never becomes key**. If it
/// did, the user's text field would lose focus and `TextInjector` would have nothing to
/// insert into. Hence `.nonactivatingPanel` plus `canBecomeKey == false` — which is also
/// what lets you *click* the pill to start dictating without pulling focus out of the app
/// you're typing in.
///
/// The panel is a fixed transparent canvas larger than any pill state; the pill grows and
/// shrinks inside it. Clicks on the transparent area fall through to whatever is underneath,
/// because AppKit hit-tests a non-opaque borderless window by its pixels.
///
/// Short-lived on purpose: `PillPresenter` makes a new one for every dictation.
@MainActor
final class HUDPanel: NSPanel {
    init(controller: DictationController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: DS.Size.pillCanvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        // Dropped by reference, never `close()`d — so AppKit must not release it on close too.
        isReleasedWhenClosed = false

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        let host = NSHostingView(rootView: FlowPill(controller: controller))
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Bottom-center of the screen with the pointer on it, just above the Dock — so the pill
    /// follows you to whichever display you're working on.
    ///
    /// The pointer's screen rather than `NSScreen.main`: `main` is the screen with the key
    /// window, and while you're dictating into another app that can be the wrong display.
    func reposition() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first
        else {
            Log.app.error("no screen available to position the flow pill")
            return
        }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.minY))
    }
}

/// Decides when the pill has a window — and makes sure it's always a *fresh* one.
///
/// **Why fresh.** After the Mac has slept, a long-lived SwiftUI window can stop redrawing when
/// its state changes, while the app's code keeps running (a known macOS/SwiftUI problem;
/// Apple's forum reports the same, and that a *new* window restores it). That was a real bug
/// here: after a 40-minute sleep, holding fn started the recording and played the start sound,
/// but the one pill window created at launch never drew the pill — until the app was
/// relaunched. So the pill no longer has a permanent window: every dictation gets a new one,
/// created the moment the key goes down (empty and transparent until the hold engages), and
/// dropped when the dictation is over. A stale window can't be reused because none is kept.
///
/// **And checked.** 0.6 s after the pill should be on screen, macOS is asked whether the window
/// is actually visible; if not, it's replaced once more. Both outcomes are logged at notice
/// level, which macOS keeps.
@MainActor
final class PillPresenter {
    private let controller: DictationController
    private var panel: HUDPanel?
    private var teardown: Task<Void, Never>?
    private var wasActive = false
    private var wasEngaged = false

    init(controller: DictationController) {
        self.controller = controller
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.reposition() }
        }
    }

    /// Call on every change to the controller's state, delivery, or the idle-pill setting.
    func sync() {
        let active = controller.state.isActive
        if active, !wasActive { replacePanel(reason: nil) }
        wasActive = active

        let engaged = controller.isEngaged
        if engaged, !wasEngaged { checkVisibilitySoon() }
        wasEngaged = engaged

        if needsWindow {
            teardown?.cancel()
            teardown = nil
            if panel == nil { replacePanel(reason: nil) }
        } else if panel != nil, teardown == nil {
            // Out at once — there's no exit animation to wait for. (Still a Task, so a
            // key-down in the same run-loop turn can cancel it and keep the window.)
            teardown = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.teardown = nil
                if !self.needsWindow { self.dropPanel() }
            }
        }
    }

    /// After sleep, screen wake or unlock: a window that outlived it (only the idle pill keeps
    /// one) is replaced. Dictations need nothing — each one makes its own anyway.
    func refresh(after reason: String) {
        guard panel != nil, !controller.state.isActive else { return }
        replacePanel(reason: reason)
    }

    /// Whether there should be a window right now. During a hold that hasn't engaged yet
    /// there is one, but it's empty and transparent — so a quick tap of fn shows nothing.
    private var needsWindow: Bool {
        switch controller.state {
        case .starting, .listening, .error: true
        // The pill vanishes on release, so its window goes too.
        case .finishing: false
        case .idle: controller.delivery != nil || Settings.shared.showIdlePill
        }
    }

    private func replacePanel(reason: String?) {
        teardown?.cancel()
        teardown = nil
        dropPanel()
        let fresh = HUDPanel(controller: controller)
        fresh.reposition()
        fresh.orderFrontRegardless()
        panel = fresh
        if let reason {
            Log.app.notice("pill: new window (\(reason, privacy: .public))")
        }
    }

    private func dropPanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// The pill should be on screen by now — make sure macOS agrees, and heal it if not.
    private func checkVisibilitySoon() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.controller.isEngaged, self.controller.state.isActive,
                  let panel = self.panel
            else { return }
            if panel.occlusionState.contains(.visible) {
                Log.app.notice("pill: on screen")
            } else {
                self.replacePanel(reason: "was not visible")
            }
        }
    }
}
