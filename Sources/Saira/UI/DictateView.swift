import AppKit
import SwiftUI

/// The home screen: one dictation card that moves through Ready → Listening → Transcribing →
/// Transcribed, with recent dictations beside it.
///
/// The mockup draws the four states as four cards side by side, which is how you *present*
/// a flow. In the app it's one card that changes, because only one of them is ever true.
struct DictateView: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared
    @State private var globeKeyAction = Permissions.globeKeyAction

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            PageHeader(eyebrow: "Dictation", title: "Your voice.", italic: "Higher productivity.")

            if !controller.isShortcutArmed {
                ShortcutOffBanner()
            } else if settings.shortcut == .fn, globeKeyAction != 0 {
                GlobeKeyWarning(action: globeKeyAction)
            }

            HStack(alignment: .top, spacing: DS.Space.roomy) {
                DictationDeck(controller: controller)
                RecentColumn(controller: controller)
                    .frame(width: DS.Size.recentWidth)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            StepsStrip()
        }
        .padding(DS.Space.page)
        .padding(.top, DS.Space.snug)
        // Pick up a change made in Keyboard settings as soon as you come back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            globeKeyAction = Permissions.globeKeyAction
        }
    }
}

// MARK: - Permission banner

/// Shown while the shortcut can't work — which is always a missing Accessibility grant.
private struct ShortcutOffBanner: View {
    @State private var settings = Settings.shared

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.roomy) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(DS.Color.warning)
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text("Your shortcut is off")
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Color.ink)
                Text("Turn on Saira in System Settings ▸ Privacy & Security ▸ Accessibility so \(settings.shortcut.displayName) works in every app. It switches on here by itself — no restart. If it's already on but this doesn't go away, use Fix.")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.base)
            Button("Fix") { Permissions.resetAndRequestAccessibility() }
                .buttonStyle(.pillSecondary)
                .help("Clears a stale permission for this app and asks again")
            Button("Open Settings") { Permissions.openAccessibilitySettings() }
                .buttonStyle(.pillPrimary)
        }
        .padding(DS.Space.roomy)
        .background(DS.Color.warningSoft, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

// MARK: - The deck

private struct DictationDeck: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    private enum Phase: Equatable {
        case ready, listening, transcribing, result, error(String)
    }

    private var phase: Phase {
        switch controller.state {
        case .starting, .listening: .listening
        case .finishing: .transcribing
        case .error(let message): .error(message)
        case .idle: controller.lastResult == nil ? .ready : .result
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .ready: ready
            case .listening: listening
            case .transcribing: transcribing
            case .result:
                if let run = controller.lastResult {
                    ResultCard(controller: controller, run: run)
                }
            case .error(let message): failure(message)
            }
        }
        .padding(DS.Space.section)
        .frame(maxWidth: .infinity, minHeight: DS.Size.deckMinHeight, maxHeight: .infinity)
        .cardStyle(radius: DS.Radius.deck)
        .animation(DS.Motion.standard, value: phase)
    }

    // MARK: Ready

    private var ready: some View {
        VStack(spacing: DS.Space.roomy) {
            Spacer(minLength: 0)
            Button { controller.toggleFromWindow() } label: {
                Image(systemName: "mic")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: DS.Size.micOrb, height: DS.Size.micOrb)
                    .background(Circle().fill(DS.Color.sunken))
                    .overlay(Circle().strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline))
                    .overlay(
                        Circle()
                            .strokeBorder(DS.Color.accent, lineWidth: DS.Space.tight)
                            .padding(-DS.Space.snug)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Start dictating")

            Text("Ready")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.ink)
                .padding(.top, DS.Space.snug)

            HStack(spacing: DS.Space.snug) {
                Text(settings.activationMode == .hold ? "Hold" : "Press")
                ShortcutKeys(shortcut: settings.shortcut)
                Text("in any app, or")
            }
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.inkSecondary)

            Button("Start dictating here") { controller.toggleFromWindow() }
                .buttonStyle(.pillPrimary)

            Spacer(minLength: 0)
            HStack(spacing: DS.Space.snug) {
                Chip(text: settings.template.title, systemImage: settings.template.symbol)
                Chip(text: "Apple · on-device", systemImage: "cpu")
                if settings.smartCleanup && settings.cleanupEnabled {
                    Chip(text: "Smart cleanup", systemImage: "sparkles")
                }
            }
        }
    }

    // MARK: Listening

    private var listening: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            HStack(spacing: DS.Space.snug) {
                StatusDot(color: DS.Color.record, pulsing: true)
                Eyebrow(text: "Recording", color: DS.Color.ink)
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
                    Text(Formatters.counter(timeline.date.timeIntervalSince(controller.recordingStartedAt ?? timeline.date)))
                        .font(DS.Font.counter)
                        .foregroundStyle(DS.Color.ink)
                }
            }

            LevelBars(
                level: controller.level,
                isActive: controller.state == .listening,
                count: 44,
                maxHeight: 76,
                color: DS.Color.ink
            )
            .frame(maxWidth: .infinity)

            ScrollView {
                Group {
                    if controller.transcript.isEmpty {
                        Text("Speak naturally…")
                            .foregroundStyle(DS.Color.inkTertiary)
                            .italic()
                    } else {
                        Text(controller.transcript)
                            .foregroundStyle(DS.Color.ink)
                    }
                }
                .font(DS.Font.quote)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)

            HStack(spacing: DS.Space.snug) {
                if controller.isHandsFree {
                    Button { controller.stop() } label: {
                        Label("Finish", systemImage: "stop.fill")
                    }
                    .buttonStyle(.pillPrimary)
                    Button("Cancel") { controller.cancel() }
                        .buttonStyle(.pillQuiet)
                } else {
                    Text("Let go of the keys to finish.")
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.inkSecondary)
                }
                Spacer()
                HStack(spacing: DS.Space.tight) {
                    Keycap(label: "esc")
                    Text("cancels")
                }
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.inkTertiary)
            }
        }
    }

    // MARK: Transcribing

    private var transcribing: some View {
        VStack(spacing: DS.Space.roomy) {
            Spacer()
            LevelBars(level: 0.25, isActive: true, count: 20, maxHeight: 34, color: DS.Color.accentInk)
            Text(settings.smartCleanup && settings.cleanupEnabled ? "Transcribing & polishing…" : "Transcribing…")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.ink)
            Text("\(settings.template.title) · on this Mac")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Error

    private func failure(_ message: String) -> some View {
        VStack(spacing: DS.Space.base) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DS.Color.warning)
            Text("That didn't work")
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.ink)
            Text(message)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Result

/// The last dictation, or one picked from Recent: read it, fix it, copy it, insert it.
private struct ResultCard: View {
    @Bindable var controller: DictationController
    let run: DictationRun

    @State private var isEditing = false
    @State private var draft = ""
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            HStack(spacing: DS.Space.snug) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DS.Color.live)
                Eyebrow(text: "Transcribed", color: DS.Color.live)
                Spacer()
                Text(Formatters.relative(run.date))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkTertiary)
                IconButton(systemImage: "xmark", help: "Close") { controller.clearResult() }
            }

            Group {
                if isEditing {
                    TextEditor(text: $draft)
                        .font(DS.Font.quote)
                        .foregroundStyle(DS.Color.ink)
                        .scrollContentBackground(.hidden)
                        .padding(DS.Space.snug)
                        .sunkenStyle()
                } else {
                    ScrollView {
                        Text("“\(run.text)”")
                            .font(DS.Font.quote)
                            .foregroundStyle(DS.Color.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if let corrections = run.corrections, !corrections.isEmpty {
                CorrectionBadges(corrections: corrections)
            }

            HStack(spacing: DS.Space.snug) {
                Text(meta)
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.inkTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if isEditing {
                    Button("Cancel") { isEditing = false }
                        .buttonStyle(.pillQuiet)
                    Button("Save") {
                        controller.updateResultText(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                        isEditing = false
                    }
                    .buttonStyle(.pillPrimary)
                } else {
                    Button {
                        controller.copyResult()
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.4))
                            didCopy = false
                        }
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.pillSecondary)

                    Button {
                        draft = run.text
                        isEditing = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(.pillSecondary)

                    Button { controller.insertResult() } label: {
                        Label("Insert", systemImage: "return")
                    }
                    .buttonStyle(.pillPrimary)
                    .help("Switch back to the app you were in and type this there")
                }
            }
        }
        .onChange(of: run.id) { _, _ in isEditing = false }
    }

    private var meta: String {
        var parts = [run.engine, Formatters.seconds(run.processSeconds)]
        if let template = run.dictationTemplate { parts.insert(template.title, at: 0) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Recent

private struct RecentColumn: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent")
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Button("See all") { AppNavigation.shared.section = .history }
                    .buttonStyle(.plain)
                    .font(DS.Font.label.weight(.medium))
                    .foregroundStyle(DS.Color.accentInk)
            }
            .padding(DS.Space.roomy)

            Rectangle().fill(DS.Color.border).frame(height: DS.Border.hairline)

            if store.runs.isEmpty {
                EmptyState(
                    systemImage: "waveform",
                    title: "Nothing yet",
                    detail: "Your dictations collect here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.hair) {
                        ForEach(store.runs.prefix(12)) { run in
                            RecentRow(run: run, isSelected: controller.lastResult?.id == run.id) {
                                controller.show(run)
                            }
                        }
                    }
                    .padding(DS.Space.snug)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .cardStyle()
    }
}

private struct RecentRow: View {
    let run: DictationRun
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.snug) {
                Image(systemName: run.dictationTemplate?.symbol ?? "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkTertiary)
                    .frame(width: DS.Space.roomy)
                    .padding(.top, DS.Space.hair)
                VStack(alignment: .leading, spacing: DS.Space.hair) {
                    Text(run.text)
                        .font(DS.Font.label.weight(.medium))
                        .foregroundStyle(isSelected ? DS.Color.onSelection : DS.Color.ink)
                        .lineLimit(1)
                    HStack {
                        Text(Formatters.relative(run.date))
                        Spacer()
                        Text(Formatters.seconds(run.processSeconds))
                            .font(DS.Font.mono)
                    }
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkTertiary)
                }
            }
            .padding(DS.Space.snug)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .fill(isSelected ? DS.Color.selection : (isHovering ? DS.Color.hover : .clear))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Steps

/// Three numbered steps along the bottom — the editorial "how it works" strip.
private struct StepsStrip: View {
    @State private var settings = Settings.shared

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.wide) {
            step("01", "Trigger anywhere", "\(settings.activationMode == .hold ? "Hold" : "Press") \(settings.shortcut.displayName) in any text field. The pill appears while it listens.")
            step("02", "Speak naturally", "Pauses, fillers and restarts are fine — they're cleaned up.")
            step("03", "It lands where you type", "Clean text is typed at your cursor. Esc cancels.")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.base) {
            Rectangle().fill(DS.Color.border).frame(width: DS.Border.hairline)
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text(number)
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.accentInk)
                Text(title)
                    .font(DS.Font.heading)
                    .foregroundStyle(DS.Color.ink)
                Text(detail)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
