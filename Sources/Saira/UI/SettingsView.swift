import AppKit
import Speech
import SwiftUI

/// Every setting, in cards. Shown in the main window's Settings section and in the standard
/// ⌘, Settings window — the same view in both places.
struct SettingsView: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                PageHeader(eyebrow: "Settings", title: "Make it", italic: "yours.")

                StartupSection()
                ShortcutSection(controller: controller)
                SpeechSection()
                AudioSection()
                CleanupSection()
                BehaviorSection()
                AppearanceSection()
                PermissionsSection()
            }
            .padding(DS.Space.page)
            .padding(.top, DS.Space.snug)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A titled settings card.
private struct SettingsCard<Content: View>: View {
    let title: String
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(spacing: DS.Space.snug) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Color.accentInk)
                Eyebrow(text: title, color: DS.Color.ink)
            }
            .padding(.bottom, DS.Space.tight)
            content
        }
        .padding(DS.Space.wide)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct Divider: View {
    var body: some View {
        Rectangle().fill(DS.Color.border).frame(height: DS.Border.hairline)
    }
}

// MARK: - Startup

/// First on the page on purpose: "does it start with my Mac" is the setting people look for.
private struct StartupSection: View {
    @State private var loginItem = LoginItem.shared

    var body: some View {
        SettingsCard(title: "Startup", symbol: "power") {
            SettingRow(title: "Start when my Mac starts", detail: loginItem.statusText) {
                HStack(spacing: DS.Space.snug) {
                    if loginItem.needsApproval {
                        Button("Allow…") { loginItem.openSystemSettings() }
                            .buttonStyle(.pillPrimary)
                    }
                    Toggle("", isOn: Binding(
                        get: { loginItem.isEnabled || loginItem.needsApproval },
                        set: { loginItem.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .tint(DS.Color.accentInk)
                    .labelsHidden()
                }
            }
            Divider()
            SettingRow(
                title: "Quit Saira",
                detail: "Closing the window or pressing ⌘Q keeps Saira listening. This is the only way to stop it."
            ) {
                Button("Quit Saira…") { AppDelegate.confirmQuit() }
                    .buttonStyle(.pillSecondary)
            }
        }
    }
}

// MARK: - Shortcut

private struct ShortcutSection: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var globeKeyAction = Permissions.globeKeyAction

    var body: some View {
        SettingsCard(title: "Shortcut", symbol: "command") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.Space.snug)], spacing: DS.Space.snug) {
                ForEach(Shortcut.allCases, id: \.self) { shortcut in
                    ShortcutTile(shortcut: shortcut, isSelected: settings.shortcut == shortcut) {
                        settings.shortcut = shortcut
                        controller.reloadHotkey()
                    }
                }
            }
            Text(settings.shortcut.detail)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)

            if settings.shortcut == .fn, globeKeyAction != 0 {
                GlobeKeyWarning(action: globeKeyAction)
            }

            Divider().padding(.top, DS.Space.snug)

            SettingRow(
                title: "Press once to toggle",
                detail: settings.activationMode == .toggle
                    ? "Press to start, press again to finish. Esc cancels."
                    : "Hold while you talk, let go to finish. Esc cancels."
            ) {
                Toggle("", isOn: Binding(
                    get: { settings.activationMode == .toggle },
                    set: { settings.activationMode = $0 ? .toggle : .hold }
                ))
                .toggleStyle(.switch)
                .tint(DS.Color.accentInk)
                .labelsHidden()
            }
        }
        // Pick up a change made in Keyboard settings as soon as you come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            globeKeyAction = Permissions.globeKeyAction
        }
    }
}

/// macOS gives the fn / Globe key its own job by default. Left alone, holding fn starts Apple's
/// dictation (or the emoji picker) on top of this app's.
struct GlobeKeyWarning: View {
    let action: Int

    private var what: String {
        switch action {
        case 1: "switches your input source"
        case 2: "opens the emoji picker"
        case 3: "starts Apple's own dictation"
        default: "does something of its own"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.base) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Color.warning)
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text("macOS also uses fn: right now it \(what).")
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.ink)
                Text("In Keyboard settings, set “Press 🌐 key to” → Do Nothing, so only Saira answers the key.")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Keyboard") { Permissions.openKeyboardSettings() }
                .buttonStyle(.pillPrimary)
        }
        .padding(DS.Space.base)
        .background(DS.Color.warningSoft, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
    }
}

private struct ShortcutTile: View {
    let shortcut: Shortcut
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.snug) {
                ShortcutKeys(shortcut: shortcut)
                    .frame(height: DS.Size.keycapHeight + DS.Border.keycapDepth)
                Text(shortcut == .optionSpace ? "Recommended" : " ")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkTertiary)
            }
            .padding(.vertical, DS.Space.base)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(isSelected ? DS.Color.selection.opacity(0.55) : DS.Color.sunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(
                        isSelected ? DS.Color.accentInk : DS.Color.border,
                        lineWidth: isSelected ? DS.Border.strong : DS.Border.hairline
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Speech

private struct SpeechSection: View {
    @State private var settings = Settings.shared
    @State private var locales: [Locale] = []

    var body: some View {
        SettingsCard(title: "Speech", symbol: "waveform") {
            SettingRow(
                title: "Language",
                detail: "Apple's speech engine, built into macOS — nothing to download, and it barely adds to the app's memory. It listens for one language at a time."
            ) {
                Picker("Language", selection: $settings.languageIdentifier) {
                    Text("System (\(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "default"))")
                        .tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }
        }
        .task {
            let supported = await SpeechTranscriber.supportedLocales
            locales = supported.sorted {
                (Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
                    < (Locale.current.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
            }
        }
    }
}

// MARK: - Audio

private struct AudioSection: View {
    @State private var settings = Settings.shared
    @State private var devices: [AudioInputDevice] = []
    @State private var micTest = MicTest()

    var body: some View {
        SettingsCard(title: "Audio", symbol: "mic") {
            SettingRow(title: "Microphone", detail: "Used for every dictation.") {
                Picker("Microphone", selection: $settings.microphoneUID) {
                    Text("System default (\(AudioDevices.defaultInputName() ?? "none"))").tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }

            SettingRow(
                title: "Test",
                detail: micTest.failure ?? (micTest.isRunning ? "Say something — the meter should move." : "Check the level before you dictate.")
            ) {
                HStack(spacing: DS.Space.base) {
                    SegmentMeter(level: micTest.level)
                    Button(micTest.isRunning ? "Stop" : "Test") {
                        if micTest.isRunning {
                            micTest.stop()
                        } else {
                            Task { await micTest.start(uid: settings.microphoneUID) }
                        }
                    }
                    .buttonStyle(.pillSecondary)
                }
            }
        }
        .onAppear { devices = AudioDevices.inputs() }
        .onDisappear { micTest.stop() }
        .onChange(of: settings.microphoneUID) { _, uid in
            // Restart on the newly chosen device, so the meter shows the right mic.
            guard micTest.isRunning else { return }
            micTest.stop()
            Task { await micTest.start(uid: uid) }
        }
    }
}

// MARK: - Cleanup

private struct CleanupSection: View {
    @State private var settings = Settings.shared

    var body: some View {
        SettingsCard(title: "Cleanup", symbol: "sparkles") {
            SettingRow(
                title: "Clean up text",
                detail: "Strips fillers, fixes spacing and capitals. Your dictionary's corrections run either way."
            ) {
                switchToggle($settings.cleanupEnabled)
            }
            Divider()
            SettingRow(
                title: "Smart cleanup",
                detail: FoundationModelFormatter.unavailableReason
                    ?? "Apple's on-device model formats lists and applies \"actually, make that…\" corrections. Slower: it can add up to 2.5 s before the text appears. Off is instant."
            ) {
                switchToggle($settings.smartCleanup)
                    .disabled(!settings.cleanupEnabled || !FoundationModelFormatter.isAvailable)
            }
        }
    }
}

// MARK: - Behavior

private struct BehaviorSection: View {
    @State private var settings = Settings.shared

    var body: some View {
        SettingsCard(title: "Behavior", symbol: "slider.horizontal.3") {
            SettingRow(title: "Insert text at cursor", detail: "Off: the text is copied, and you paste it yourself.") {
                switchToggle($settings.insertAtCursor)
            }
            Divider()
            SettingRow(title: "Auto-copy to clipboard", detail: "Also leave every dictation on the clipboard.") {
                switchToggle($settings.autoCopy)
            }
            Divider()
            SettingRow(title: "Show the pill when idle", detail: "Off: the pill only appears while you hold the shortcut. On: a tiny pill stays at the bottom of the screen, and clicking it dictates.") {
                switchToggle($settings.showIdlePill)
            }
            Divider()
            SettingRow(title: "Sound effects", detail: "A tick when listening starts, a pop when text lands.") {
                switchToggle($settings.soundEnabled)
            }
            Divider()
            SettingRow(title: "Voice bubbles", detail: "Little bubbles rise off the pill as you talk — more when you're louder, a bigger one for each word.") {
                switchToggle($settings.voiceBubbles)
            }
        }
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @State private var settings = Settings.shared

    var body: some View {
        SettingsCard(title: "Appearance", symbol: "circle.lefthalf.filled") {
            SettingRow(title: "Theme", detail: "Paper by day, charcoal by night — or pick one.") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsSection: View {
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasMicrophone = Permissions.hasMicrophone

    var body: some View {
        SettingsCard(title: "Permissions", symbol: "lock.shield") {
            permission(
                "Accessibility",
                detail: "Lets the shortcut work in every app, and types the text for you.",
                granted: hasAccessibility,
                open: Permissions.openAccessibilitySettings
            )
            Divider()
            permission(
                "Microphone",
                detail: "Only while you're dictating or testing the mic.",
                granted: hasMicrophone,
                open: Permissions.openMicrophoneSettings
            )
            Divider()
            SettingRow(title: "Your data", detail: "History and dictionary are plain files on this Mac.") {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppPaths.support])
                }
                .buttonStyle(.pillQuiet)
            }
        }
        // There's no notification for a TCC change; refresh whenever the user comes back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = Permissions.hasAccessibility
            hasMicrophone = Permissions.hasMicrophone
        }
    }

    private func permission(_ title: String, detail: String, granted: Bool, open: @escaping () -> Void) -> some View {
        SettingRow(title: title, detail: detail) {
            if granted {
                Chip(text: "Granted", systemImage: "checkmark", tint: DS.Color.live, fill: DS.Color.liveSoft)
            } else {
                Button("Grant…", action: open)
                    .buttonStyle(.pillPrimary)
            }
        }
    }
}

// MARK: - Helpers

@MainActor
private func switchToggle(_ isOn: Binding<Bool>) -> some View {
    Toggle("", isOn: isOn)
        .toggleStyle(.switch)
        .tint(DS.Color.accentInk)
        .labelsHidden()
}
