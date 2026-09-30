import AppKit
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

        let hud = HUDPanel(controller: controller)
        self.hud = hud
        hud.sync()

        if !controller.activate() {
            Permissions.promptForAccessibility()
            // The tap can only be created once the user grants Accessibility, and there's
            // no notification for that — poll until it takes.
            retryActivation()
        }

        observeForPill()
        Log.app.info("Saira ready — \(Settings.shared.shortcut.displayName, privacy: .public) to dictate")
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.deactivate()
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

    /// Keeps trying until the shortcut is live. There's no notification for a TCC grant, and
    /// `AXIsProcessTrusted` can report true a beat before a tap can actually be created — so
    /// the loop waits for the tap itself, not the flag.
    private func retryActivation() {
        Task { @MainActor in
            while !controller.isShortcutArmed {
                try? await Task.sleep(for: .seconds(1))
                if Permissions.hasAccessibility { controller.activate() }
            }
            Log.app.info("Accessibility granted — shortcut armed")
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

        Button("Quit Saira") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        switch controller.state {
        case .starting, .listening: "Listening…"
        case .finishing: "Transcribing…"
        case .error(let message): message
        case .idle:
            "\(settings.activationMode == .hold ? "Hold" : "Press") \(settings.shortcut.displayName) to dictate"
        }
    }
}
