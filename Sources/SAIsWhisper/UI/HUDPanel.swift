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
@MainActor
final class HUDPanel: NSPanel {
    private let controller: DictationController

    init(controller: DictationController) {
        self.controller = controller
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

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        let host = NSHostingView(rootView: FlowPill(controller: controller))
        host.sizingOptions = []
        contentView = host

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows or hides the panel to match the controller and settings. The pill animates
    /// its own states; this only decides whether there's a window at all.
    func sync() {
        let needsWindow = needsWindowNow

        if needsWindow, !isVisible {
            reposition()
            orderFrontRegardless()
        } else if !needsWindow, isVisible {
            // Let the pill's own exit transition play before the window goes.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                if !self.needsWindowNow { self.orderOut(nil) }
            }
        }
    }

    /// A hold that hasn't engaged yet gets no window — a tap of fn must not flash anything.
    private var needsWindowNow: Bool {
        switch controller.state {
        case .starting, .listening: controller.isEngaged
        case .finishing, .error: true
        case .idle: controller.delivery != nil || Settings.shared.showIdlePill
        }
    }

    /// Bottom-center of the screen with the pointer on it, just above the Dock. Called each
    /// time the pill appears, so it follows you to whichever display you're working on.
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
