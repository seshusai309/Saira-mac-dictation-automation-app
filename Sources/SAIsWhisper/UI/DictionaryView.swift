import WhisperDictionary
import AppKit
import SwiftUI

/// The dictionary: add, edit, delete, search.
///
/// Both entry kinds live in one list rather than separate tabs — they're two shapes of the
/// same idea and you want to see everything you've taught it at once. The kind is carried by
/// a chip on each row.
struct DictionaryView: View {
    @State private var store = DictionaryStore.shared
    @State private var query = ""
    @State private var editing: DictionaryEntry?
    @State private var isAdding = false

    private var entries: [DictionaryEntry] { store.filtered(by: query) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.wide) {
            PageHeader(eyebrow: "Dictionary", title: "Teach it", italic: "your words.") {
                // The path is offered because the dictionary is meant to be editable outside
                // the UI too — which is only true if you can find the file.
                Button("Open dictionary.txt") {
                    NSWorkspace.shared.activateFileViewerSelecting([DictionaryStore.fileURL])
                }
                .buttonStyle(.pillQuiet)
                .help(DictionaryStore.fileURL.path)
            }

            HStack(spacing: DS.Space.snug) {
                SearchField(text: $query, placeholder: "Search dictionary")
                Button { isAdding = true } label: {
                    Label("Add word", systemImage: "plus")
                }
                .buttonStyle(.pillPrimary)
                .keyboardShortcut("n", modifiers: .command)
            }

            if entries.isEmpty {
                EmptyState(
                    systemImage: "character.book.closed",
                    title: store.entries.isEmpty ? "Nothing taught yet" : "No matches",
                    detail: store.entries.isEmpty
                        ? "Add names, jargon and product words it keeps getting wrong."
                        : "Try a different search."
                )
                .cardStyle()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            DictionaryRow(
                                entry: entry,
                                onEdit: { editing = entry },
                                onToggle: {
                                    var updated = entry
                                    updated.isEnabled.toggle()
                                    store.update(updated)
                                },
                                onDelete: { store.delete(entry) }
                            )
                            if entry.id != entries.last?.id {
                                Rectangle().fill(DS.Color.border).frame(height: DS.Border.hairline)
                                    .padding(.horizontal, DS.Space.roomy)
                            }
                        }
                    }
                    .padding(.vertical, DS.Space.tight)
                }
                .cardStyle()

                Text("\(store.entries.count) entr\(store.entries.count == 1 ? "y" : "ies") · words steer the engine, corrections rewrite what it heard")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkTertiary)
            }
        }
        .padding(DS.Space.page)
        .padding(.top, DS.Space.snug)
        .sheet(isPresented: $isAdding) {
            DictionaryEditor(entry: nil) { store.add($0) }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditor(entry: entry) { store.update($0) }
        }
    }
}

// MARK: - Row

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.base) {
            Chip(
                text: entry.kind == .correction ? "Fix" : "Word",
                tint: entry.kind == .correction ? DS.Color.live : DS.Color.accentInk,
                fill: entry.kind == .correction ? DS.Color.liveSoft : DS.Color.selection.opacity(0.6)
            )
            .frame(width: 52, alignment: .leading)

            if entry.kind == .correction {
                Text(entry.hear)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkTertiary)
                    .strikethrough(color: DS.Color.inkTertiary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Color.inkTertiary)
            }

            Text(entry.write)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.ink)

            Spacer()

            HStack(spacing: DS.Space.hair) {
                IconButton(systemImage: "pencil", help: "Edit", action: onEdit)
                IconButton(
                    systemImage: entry.isEnabled ? "pause.circle" : "play.circle",
                    help: entry.isEnabled ? "Turn off without deleting" : "Turn back on",
                    action: onToggle
                )
                IconButton(systemImage: "trash", help: "Delete", action: onDelete)
            }
            .opacity(isHovering ? 1 : 0)
        }
        .opacity(entry.isEnabled ? 1 : 0.45)
        .padding(.horizontal, DS.Space.roomy)
        .padding(.vertical, DS.Space.snug)
        .background(isHovering ? DS.Color.hover : .clear)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Editor

/// Add or edit one entry, with the false-positive warning shown live as you type.
private struct DictionaryEditor: View {
    let entry: DictionaryEntry?
    let onSave: (DictionaryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: DictionaryEntry.Kind
    @State private var hear: String
    @State private var write: String

    init(entry: DictionaryEntry?, onSave: @escaping (DictionaryEntry) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _kind = State(initialValue: entry?.kind ?? .term)
        _hear = State(initialValue: entry?.hear ?? "")
        _write = State(initialValue: entry?.write ?? "")
    }

    private var draft: DictionaryEntry {
        DictionaryEntry(
            id: entry?.id ?? UUID(),
            kind: kind,
            write: write.trimmingCharacters(in: .whitespacesAndNewlines),
            hear: kind == .correction ? hear.trimmingCharacters(in: .whitespacesAndNewlines) : "",
            isEnabled: entry?.isEnabled ?? true
        )
    }

    private var warnings: [DictionaryWarning] { DictionaryWarning.check(draft) }

    private var isValid: Bool {
        !draft.write.isEmpty && (kind == .term || !draft.hear.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.roomy) {
            Text("\(Text(entry == nil ? "New" : "Edit").font(DS.Font.title))\(Text(" entry").font(DS.Font.titleItalic))")
                .foregroundStyle(DS.Color.ink)

            Picker("Kind", selection: $kind.animation(DS.Motion.standard)) {
                Text("A word it should know").tag(DictionaryEntry.Kind.term)
                Text("A correction").tag(DictionaryEntry.Kind.correction)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: DS.Space.base) {
                if kind == .correction {
                    field("When you hear", text: $hear, prompt: "cloud code")
                }
                field(
                    kind == .correction ? "Write" : "Word or phrase",
                    text: $write,
                    prompt: kind == .correction ? "Claude Code" : "Anthropic"
                )
            }

            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: DS.Space.snug) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Color.warning)
                    Text(warning.message)
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Space.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.warningSoft, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            }

            HStack(spacing: DS.Space.snug) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.pillQuiet)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard isValid else { return }
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.pillPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(DS.Space.section)
        .frame(width: 460)
        .background(PaperBackground())
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Eyebrow(text: label)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, DS.Space.base)
                .frame(height: DS.Size.fieldHeight)
                .sunkenStyle()
        }
    }
}
