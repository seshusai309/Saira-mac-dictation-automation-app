import AppKit
import Carbon
import SwiftUI

@main
struct SairaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Never restore saved window state. When the main window was closed at quit, macOS
        // "restores" that — launching with no window, which reads as the app not opening —
        // and it overrides `.defaultLaunchBehavior(.presented)`. Set here, before AppKit
        // looks for state to restore.
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")
    }

    var body: some Scene {
        // A `Window` rather than a `WindowGroup`: this app has one main window, and letting
        // ⌘N spawn a second copy makes no sense.
        Window("Saira", id: "main") {
            MainWindow(controller: delegate.controller)
        }
        .windowStyle(.hiddenTitleBar)
        // Open on every launch. Without this, closing the window once makes macOS "restore"
        // that on the next launch — the app starts with no window at all, only the menu-bar
        // icon, and looks like it didn't open.
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // ⌘Q only closes the window — Saira keeps listening. Quitting is deliberate:
            // "Quit Saira…" asks first.
            CommandGroup(replacing: .appTermination) {
                Button("Close Saira Window") { AppDelegate.closeMainWindow() }
                    .keyboardShortcut("q")
                Button("Quit Saira…") { AppDelegate.confirmQuit() }
            }
            CommandMenu("Dictation") {
                Button("Start or Finish Dictation") { delegate.controller.toggleFromWindow() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                // No key equivalent: Esc is caught by the event tap while dictating, and
                // claiming it here would steal it from sheets and text fields.
                Button("Cancel Dictation (Esc)") { delegate.controller.cancel() }
                Divider()
                Menu("Template") {
                    ForEach(DictationTemplate.allCases) { template in
                        Button(template.title) { Settings.shared.template = template }
                    }
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Reveal Data Folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.support])
                }
            }
        }

        // Fully qualified: this app has its own `Settings` type, which otherwise shadows
        // SwiftUI's settings scene.
        SwiftUI.Settings {
            SettingsView(controller: delegate.controller)
                .frame(width: 640, height: 720)
                .background(PaperBackground())
        }

        // Secondary: status, the template, and a way back to the window while you're
        // working in another app.
        MenuBarExtra {
            MenuContent(controller: delegate.controller)
        } label: {
            Image(systemName: delegate.controller.state.isActive ? "waveform.circle.fill" : "waveform")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var hud: HUDPanel?
    /// Held for the app's lifetime: opts out of App Nap, which throttles a background app and
    /// makes macOS switch its event tap off — the shortcut would then miss presses.
    private var backgroundActivity: NSObjectProtocol?
    private var watchdog: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Settings.shared.applyTheme()
        #if DEBUG
        // Snapshot runs launch a throwaway copy from the build folder; never register that.
        if DesignSnapshots.directory == nil { LoginItem.shared.enableOnFirstLaunch() }
        #else
        LoginItem.shared.enableOnFirstLaunch()
        #endif
        RunStore.shared.reload()

        #if DEBUG
        // Design snapshots draw the screens and quit — no shortcut, no permission prompts.
        if DesignSnapshots.directory != nil {
            DesignSnapshots.run(controller: controller)
            return
        }
        #endif

        stayAlive()

        let hud = HUDPanel(controller: controller)
        self.hud = hud
        hud.sync()

        if !controller.activate() {
            Permissions.promptForAccessibility()
        }
        startWatchdog()

        observeForPill()
        Log.app.info("Saira ready — \(Settings.shared.shortcut.displayName, privacy: .public) to dictate")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.deactivate()
    }

    // MARK: - Always listening

    /// Saira's whole job happens with no window open, and macOS treats a windowless background
    /// app as fair game: *Automatic Termination* quietly ends it to reclaim memory (the Dock
    /// and menu bar can lag behind, so it looks like it's still there), and *App Nap* throttles
    /// it until the system switches its event tap off. Either one means holding the key does
    /// nothing until the app is relaunched. Opt out of both, for as long as it runs.
    private func stayAlive() {
        let info = ProcessInfo.processInfo
        info.disableAutomaticTermination("Saira listens for its shortcut from the background")
        info.disableSuddenTermination()
        backgroundActivity = info.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Listening for the dictation shortcut"
        )
    }

    /// Checks the shortcut every two seconds, and straight away after sleep, screen wake or a
    /// switch back to this user — the moments macOS is most likely to have switched it off.
    /// Also what arms it once Accessibility is first granted.
    private func startWatchdog() {
        watchdog = Task { @MainActor [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                tick += 1
                self.controller.keepShortcutAlive()
                self.controller.updateSecureInput(holder: Permissions.secureInputHolder)
                // The safety net: whatever silenced it, a fresh listener every 10 seconds
                // means the shortcut is never dead for longer than that.
                if tick.isMultiple(of: 5) {
                    self.controller.rebuildShortcut(reason: "periodic")
                }
            }
        }

        // The moments a listener is most likely to have gone deaf: rebuild right away.
        let workspace = NSWorkspace.shared.notificationCenter
        let moments: [(Notification.Name, String)] = [
            (NSWorkspace.didWakeNotification, "wake"),
            (NSWorkspace.screensDidWakeNotification, "screen wake"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "user switch"),
        ]
        for (name, reason) in moments {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.controller.rebuildShortcut(reason: reason) }
            }
        }
        // Unlocking also ends the lock screen's Secure Input.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.rebuildShortcut(reason: "unlock") }
        }
        // Bringing Saira forward is what used to "fix" it — so do that for free.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.rebuildShortcut(reason: "app activated") }
        }
    }

    // MARK: - Quitting only on purpose

    /// Set only by the confirmation in `confirmQuit()`.
    private static var quitConfirmed = false

    /// The red ✕ closes the window; Saira keeps running and listening.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Every other way of quitting — ⌘Q, the Dock's Quit, a script — just closes the window.
    /// Saira keeps listening. It quits only after "Quit Saira…" is confirmed, or when macOS is
    /// logging out, restarting or shutting down (never block that).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.quitConfirmed || Self.isSystemEndingSession { return .terminateNow }
        Self.closeMainWindow()
        return .terminateCancel
    }

    static func closeMainWindow() {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }?.close()
    }

    /// "Are you sure?" — the one way to stop Saira.
    static func confirmQuit() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Quit Saira?"
        alert.informativeText = "Holding your shortcut won't dictate until you open Saira again. "
            + "(It also starts by itself the next time your Mac starts.)"
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        quitConfirmed = true
        NSApp.terminate(nil)
    }

    /// Whether this quit comes from macOS ending the session — logout, restart or shutdown.
    private static var isSystemEndingSession: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEQuitApplication)
        else { return false }
        let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
            ?? event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        guard let reason else { return false }
        let endingReasons = [kAEQuitAll, kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart,
                             kAEShowShutdownDialog, kAEShutDown].map { OSType($0) }
        return endingReasons.contains(reason)
    }

    /// Clicking the Dock icon with no window open brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.showMainWindow() }
        return true
    }

    /// Brings the main window forward — and recreates it if it was closed, which a closed
    /// SwiftUI `Window` needs: it's gone from `NSApp.windows`, so only SwiftUI's own
    /// `openWindow` action can bring it back.
    static func showMainWindow() {
        NSApp.activate()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }),
           window.isVisible || window.isMiniaturized {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            AppNavigation.shared.openMainWindow?(id: "main")
        }
    }

    /// Keeps the pill's window in step with the controller and the idle-pill setting.
    private func observeForPill() {
        withObservationTracking {
            _ = controller.state
            _ = controller.isEngaged
            _ = controller.delivery
            _ = Settings.shared.showIdlePill
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.hud?.sync()
                self.observeForPill()
            }
        }
    }
}

private struct MenuContent: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(statusLine)

        Divider()

        Button(controller.state.isActive ? "Finish Dictation" : "Start Dictation") {
            controller.togglePill()
        }

        Picker("Template", selection: $settings.template) {
            ForEach(DictationTemplate.allCases) { template in
                Text(template.title).tag(template)
            }
        }

        Toggle("Smart cleanup", isOn: $settings.smartCleanup)
            .disabled(!FoundationModelFormatter.isAvailable || !settings.cleanupEnabled)

        Toggle("Start at Login", isOn: Binding(
            get: { LoginItem.shared.isEnabled },
            set: { LoginItem.shared.setEnabled($0) }
        ))

        Divider()

        Button("Open Saira") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")

        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        .keyboardShortcut(",")

        if !Permissions.hasAccessibility {
            Button("Grant Accessibility…") { Permissions.openAccessibilitySettings() }
        }
        if !Permissions.hasMicrophone {
            Button("Grant Microphone…") { Permissions.openMicrophoneSettings() }
        }

        Divider()

        Button("Quit Saira…") { AppDelegate.confirmQuit() }
    }

    private var statusLine: String {
        if let holder = controller.secureInputHolder, !controller.state.isActive {
            return "Shortcut paused — \(holder) is using Secure Input"
        }
        return switch controller.state {
        case .starting, .listening: "Listening…"
        case .finishing: "Transcribing…"
        case .error(let message): message
        case .idle:
            "\(settings.activationMode == .hold ? "Hold" : "Press") \(settings.shortcut.displayName) to dictate"
        }
    }
}
