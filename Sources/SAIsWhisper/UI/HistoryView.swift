import AppKit
import SwiftUI

/// Every dictation, searchable, each copyable, with the dictionary's corrections shown.
struct HistoryView: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var isConfirmingClear = false

    enum Filter: String, CaseIterable, Identifiable {
        case all, today, week, corrected
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .today: "Today"
            case .week: "This week"
            case .corrected: "Corrected"
            }
        }
    }

    private var runs: [DictationRun] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.runs.filter { run in
            let passesFilter = switch filter {
            case .all: true
            case .today: calendar.isDateInToday(run.date)
            case .week: run.date >= weekAgo
            case .corrected: !(run.corrections ?? []).isEmpty
            }
            return passesFilter && (trimmed.isEmpty || run.text.localizedStandardContains(trimmed))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            PageHeader(eyebrow: "History", title: "Everything", italic: "you've said.") {
                Text("\(store.runs.count) dictation\(store.runs.count == 1 ? "" : "s") · \(totalWords) words")
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.inkTertiary)
            }

            HStack(spacing: DS.Space.snug) {
                SearchField(text: $query, placeholder: "Search transcriptions")
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if runs.isEmpty {
                EmptyState(
                    systemImage: store.runs.isEmpty ? "waveform" : "magnifyingglass",
                    title: store.runs.isEmpty ? "No dictations yet" : "No matches",
                    detail: store.runs.isEmpty
                        ? "Hold \(Settings.shared.shortcut.displayName) anywhere and start talking."
                        : "Try a different search or filter."
                )
                .cardStyle()
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.snug) {
                        ForEach(runs) { run in
                            HistoryRow(run: run) {
                                controller.show(run)
                                AppNavigation.shared.section = .dictate
                            }
                        }
                    }
                    .padding(.bottom, DS.Space.roomy)
                }

                HStack {
                    Spacer()
                    Button("Delete all…") { isConfirmingClear = true }
                        .buttonStyle(.pillQuiet)
                }
            }
        }
        .padding(DS.Space.page)
        .padding(.top, DS.Space.snug)
        // Confirmed, unlike a single row: one row is trivially re-recorded, the whole
        // history is not, and there's no undo.
        .confirmationDialog(
            "Delete all \(store.runs.count) dictations?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                RunLog.clear()
                controller.clearResult()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var totalWords: Int {
        store.runs.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }
}

private struct HistoryRow: View {
    let run: DictationRun
    let onOpen: () -> Void

    @State private var didCopy = false
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.snug) {
            HStack(spacing: DS.Space.snug) {
                if let template = run.dictationTemplate {
                    Chip(text: template.title, systemImage: template.symbol)
                }
                Text(Formatters.relative(run.date))
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkTertiary)
                Text("·").foregroundStyle(DS.Color.inkTertiary)
                Text("\(run.engine) · \(Formatters.seconds(run.processSeconds))")
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.inkTertiary)
                Spacer()
                HStack(spacing: DS.Space.hair) {
                    IconButton(systemImage: didCopy ? "checkmark" : "doc.on.doc", help: "Copy") { copy() }
                    IconButton(systemImage: "arrow.up.forward.square", help: "Open on the Dictate screen", action: onOpen)
                    IconButton(systemImage: "trash", help: "Delete this dictation") {
                        withAnimation(DS.Motion.standard) { RunLog.delete(run) }
                    }
                }
                // Delete appears on hover and doesn't confirm — a single transcript is cheap
                // to redo. The irreversible one is "Delete all", which does confirm.
                .opacity(isHovering ? 1 : 0.35)
            }

            Text(run.text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let corrections = run.corrections, !corrections.isEmpty {
                CorrectionBadges(corrections: corrections)
            }
        }
        .padding(DS.Space.roomy)
        .cardStyle(radius: DS.Radius.control + DS.Space.tight)
        .onHover { isHovering = $0 }
    }

    private func copy() {
        TextInjector.copy(run.text)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            didCopy = false
        }
    }
}
