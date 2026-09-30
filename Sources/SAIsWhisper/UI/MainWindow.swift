import AppKit
import SwiftUI

/// Which screen the main window shows. Shared, so the menu bar, keyboard shortcuts and
/// "See all" links can all move it.
@MainActor
@Observable
final class AppNavigation {
    static let shared = AppNavigation()

    enum Section: String, CaseIterable, Identifiable {
        case dictate
        case history
        case templates
        case dictionary
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dictate: "Dictate"
            case .history: "History"
            case .templates: "Templates"
            case .dictionary: "Dictionary"
            case .settings: "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .dictate: "mic"
            case .history: "clock"
            case .templates: "square.text.square"
            case .dictionary: "character.book.closed"
            case .settings: "gearshape"
            }
        }

        /// ⌘1…⌘5.
        var key: KeyEquivalent {
            KeyEquivalent(Character(String((Self.allCases.firstIndex(of: self) ?? 0) + 1)))
        }
    }

    var section: Section = .dictate

    /// SwiftUI's action for opening the main window, kept from the first time it appeared.
    /// It stays valid after the window closes, which is what lets a Dock click reopen it.
    @ObservationIgnored var openMainWindow: OpenWindowAction?
}

/// The app's one window: a paper sidebar and the selected screen.
struct MainWindow: View {
    @Bindable var controller: DictationController
    @State private var navigation = AppNavigation.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(controller: controller, navigation: navigation)
                .frame(width: DS.Size.sidebarWidth)

            Rectangle()
                .fill(DS.Color.border)
                .frame(width: DS.Border.hairline)
                .ignoresSafeArea()

            Group {
                switch navigation.section {
                case .dictate: DictateView(controller: controller)
                case .history: HistoryView(controller: controller)
                case .templates: TemplatesView()
                case .dictionary: DictionaryView()
                case .settings: SettingsView(controller: controller)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .animation(DS.Motion.standard, value: navigation.section)
        }
        .background(PaperBackground())
        .frame(minWidth: DS.Size.windowMin.width, minHeight: DS.Size.windowMin.height)
        .onAppear { navigation.openMainWindow = openWindow }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Bindable var controller: DictationController
    @Bindable var navigation: AppNavigation
    @State private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.snug) {
                AppMark()
                VStack(alignment: .leading, spacing: 0) {
                    Text("SAI's Whisper")
                        .font(DS.Font.wordmark)
                        .foregroundStyle(DS.Color.ink)
                    Text("Retro edition")
                        .font(DS.Font.caption.italic())
                        .foregroundStyle(DS.Color.inkTertiary)
                }
            }
            .padding(.horizontal, DS.Space.roomy)
            .padding(.top, DS.Size.titlebarInset)
            .padding(.bottom, DS.Space.wide)

            VStack(spacing: DS.Space.hair) {
                ForEach(AppNavigation.Section.allCases) { section in
                    NavRow(section: section, isSelected: navigation.section == section) {
                        navigation.section = section
                    }
                }
            }
            .padding(.horizontal, DS.Space.snug)

            Spacer()

            status
                .padding(.horizontal, DS.Space.roomy)
                .padding(.bottom, DS.Space.roomy)

            Rectangle().fill(DS.Color.border).frame(height: DS.Border.hairline)

            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text("“Turn your thoughts\ninto progress.”")
                    .font(DS.Font.body.italic())
                    .fontDesign(.serif)
                    .foregroundStyle(DS.Color.inkSecondary)
                Text("v\(Bundle.main.shortVersion) · on-device")
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.inkTertiary)
            }
            .padding(DS.Space.roomy)
        }
        .background(PaperBackground(color: DS.Color.sidebar))
    }

    /// The ready light: what the shortcut is, and whether it's armed.
    private var status: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(spacing: DS.Space.snug) {
                StatusDot(color: statusColor, pulsing: controller.state.isActive)
                Text(statusText)
                    .font(DS.Font.label.weight(.medium))
                    .foregroundStyle(DS.Color.ink)
            }
            HStack(spacing: DS.Space.tight) {
                Text(settings.activationMode == .hold ? "Hold" : "Press")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkTertiary)
                ShortcutKeys(shortcut: settings.shortcut)
            }
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .starting, .listening: DS.Color.record
        case .finishing: DS.Color.accentInk
        case .error: DS.Color.warning
        case .idle: controller.isShortcutArmed ? DS.Color.live : DS.Color.warning
        }
    }

    private var statusText: String {
        switch controller.state {
        case .starting, .listening: "Listening"
        case .finishing: "Transcribing"
        case .error: "Something went wrong"
        case .idle: controller.isShortcutArmed ? "Ready anywhere" : "Shortcut is off"
        }
    }
}

private struct NavRow: View {
    let section: AppNavigation.Section
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.base) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: DS.Space.roomy + DS.Space.tight)
                Text(section.title)
                    .font(DS.Font.bodyEmphasis)
                Spacer()
            }
            .foregroundStyle(isSelected ? DS.Color.onSelection : DS.Color.inkSecondary)
            .padding(.horizontal, DS.Space.base)
            .frame(height: DS.Size.navRowHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(isSelected ? DS.Color.selection : (isHovering ? DS.Color.hover : .clear))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(section.key, modifiers: .command)
        .onHover { isHovering = $0 }
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}
