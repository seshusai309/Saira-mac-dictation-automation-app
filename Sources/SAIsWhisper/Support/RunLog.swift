import WhisperDictionary
import Foundation
import Observation

/// One completed dictation.
struct DictationRun: Codable, Sendable, Identifiable, Equatable {
    /// Stable identity, so a single run can be edited or deleted without matching on text.
    ///
    /// Decoded leniently: runs written before this existed have no `id` field, and failing
    /// their whole line would throw away history. Those get a fresh id on load, which is
    /// persisted the next time the file is rewritten.
    var id: UUID = UUID()

    let date: Date
    let engine: String
    /// How long the key was held.
    let audioSeconds: Double
    /// Release → final text ready. This is the latency you actually feel.
    let processSeconds: Double
    /// Editable from the Dictate screen, so a fix made before inserting sticks in history.
    var text: String

    /// Dictionary corrections that fired on this transcript. Recorded so history can show
    /// whether the dictionary is actually doing anything, rather than leaving it to faith.
    var corrections: [AppliedCorrection]?

    /// The template's raw value at the time. Optional: older runs predate templates.
    var template: String?

    var dictationTemplate: DictationTemplate? { template.flatMap(DictationTemplate.init(rawValue:)) }

    init(
        id: UUID = UUID(),
        date: Date,
        engine: String,
        audioSeconds: Double,
        processSeconds: Double,
        text: String,
        corrections: [AppliedCorrection]? = nil,
        template: String? = nil
    ) {
        self.id = id
        self.date = date
        self.engine = engine
        self.audioSeconds = audioSeconds
        self.processSeconds = processSeconds
        self.text = text
        self.corrections = corrections
        self.template = template
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        engine = try container.decode(String.self, forKey: .engine)
        audioSeconds = try container.decode(Double.self, forKey: .audioSeconds)
        processSeconds = try container.decode(Double.self, forKey: .processSeconds)
        text = try container.decode(String.self, forKey: .text)
        corrections = try container.decodeIfPresent([AppliedCorrection].self, forKey: .corrections)
        template = try container.decodeIfPresent(String.self, forKey: .template)
    }
}

/// Appends every dictation to a JSONL file — one line per run, readable with any tool.
@MainActor
enum RunLog {
    private static var runsURL: URL { AppPaths.support.appendingPathComponent("runs.jsonl") }

    static func record(_ run: DictationRun) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(run) else { return }
        line.append(0x0A) // newline

        if let handle = try? FileHandle(forWritingTo: runsURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: runsURL)
        }
        RunStore.shared.reload()
    }

    static func load() -> [DictationRun] {
        guard let data = try? Data(contentsOf: runsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(DictationRun.self, from: Data(line))
        }
    }

    /// Replaces one run in place, matched by id.
    static func update(_ run: DictationRun) {
        rewrite(load().map { $0.id == run.id ? run : $0 })
    }

    static func delete(_ run: DictationRun) {
        rewrite(load().filter { $0.id != run.id })
    }

    static func clear() {
        try? FileManager.default.removeItem(at: runsURL)
        RunStore.shared.reload()
    }

    /// Replaces the whole file. Editing and deleting can't be appends, and rewriting also
    /// persists the ids that older runs were assigned on load.
    private static func rewrite(_ runs: [DictationRun]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let body = runs.compactMap { run -> String? in
            guard let data = try? encoder.encode(run) else { return nil }
            return String(data: data, encoding: .utf8)
        }.joined(separator: "\n")

        // Atomic: a partial write here would lose history that the user didn't ask to delete.
        try? (body.isEmpty ? "" : body + "\n")
            .write(to: runsURL, atomically: true, encoding: .utf8)

        RunStore.shared.reload()
    }
}

/// Live, observable history for the views. Newest first.
@MainActor
@Observable
final class RunStore {
    static let shared = RunStore()

    private(set) var runs: [DictationRun] = []

    private init() { reload() }

    func reload() {
        runs = RunLog.load().reversed()
    }
}
