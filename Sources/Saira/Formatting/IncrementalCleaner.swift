import Foundation

/// Smart cleanup that happens *while you talk*, so there's almost nothing left to do when you
/// let go.
///
/// Measured on the target Mac, one pass of the on-device model costs about 0.6 s even for a
/// short sentence (it has to write the text out), and 6 s when the model is cold. Running that
/// on the whole transcript after the key is released is what made smart cleanup feel slow.
///
/// Instead, every sentence the speech engine *commits* is handed to the model straight away,
/// one at a time, while the speaker carries on. On release:
/// - sentences already cleaned are used as they are;
/// - one still in flight gets a short grace period (`finish`'s budget), then falls back;
/// - whatever wasn't reached — usually just the last sentence — gets the instant rule-based
///   pass.
///
/// So the wait after release is roughly the rule pass plus the grace period, not a model call.
/// A dictation short enough that no sentence finished before release has nothing to reuse;
/// `finish` returns nil and the caller does the normal single full pass.
@MainActor
final class IncrementalCleaner {
    private let template: DictationTemplate
    private var jobs: [(source: String, task: Task<String, Never>)] = []

    init(template: DictationTemplate) {
        self.template = template
    }

    /// Templates whose output depends on seeing every sentence together — a checklist, an
    /// email's paragraphs — aren't cleaned sentence by sentence.
    static func supports(_ template: DictationTemplate) -> Bool {
        template != .tasks && template != .content
    }

    /// The text the engine has committed so far. Starts a cleanup for each newly finished
    /// sentence. Committed text only ever grows, so earlier sentences never change.
    func update(committed: String) {
        let sentences = Self.split(committed).sentences
        guard sentences.count > jobs.count else { return }
        for sentence in sentences[jobs.count...] {
            let previous = jobs.last?.task
            let template = template
            // One at a time, in order: the model is quickest serially, and a queue keeps the
            // newest sentence from waiting behind a pile of concurrent requests.
            let task = Task {
                _ = await previous?.value
                return await FoundationModelFormatter(template: template, isSentenceOfLonger: true)
                    .format(sentence)
            }
            jobs.append((sentence, task))
        }
    }

    /// Assembles the cleaned text for the final transcript.
    ///
    /// - Returns: nil when nothing was cleaned ahead of time — the caller should run the
    ///   normal full pass instead.
    func finish(full: String, budget: Duration) async -> String? {
        defer { cancel() }
        guard !jobs.isEmpty else { return nil }

        let (sentences, tail) = Self.split(full)
        let rules = RuleBasedFormatter(template: template)
        let deadline = ContinuousClock.now + budget
        var pieces: [String] = []
        var reused = 0

        for (index, sentence) in sentences.enumerated() {
            if index < jobs.count, jobs[index].source == sentence,
               let cleaned = await Self.value(of: jobs[index].task, before: deadline) {
                pieces.append(cleaned)
                reused += 1
            } else {
                pieces.append(await rules.format(sentence))
            }
        }
        if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pieces.append(await rules.format(tail))
        }

        Log.speech.notice("""
            cleanup: \(reused, privacy: .public) of \(sentences.count, privacy: .public) sentence(s) cleaned while talking
            """)
        return pieces.filter { !$0.isEmpty }.joined(separator: " ")
    }

    func cancel() {
        jobs.forEach { $0.task.cancel() }
        jobs.removeAll()
    }

    /// The job's result if it lands before the deadline, nil otherwise.
    private static func value(of task: Task<String, Never>, before deadline: ContinuousClock.Instant) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Splits text into finished sentences — ending in `.`, `!` or `?` followed by a space or
    /// the end — and the unfinished remainder. A decimal like "3.5" doesn't split.
    static func split(_ text: String) -> (sentences: [String], tail: String) {
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            guard ".!?".contains(character) else { continue }
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if next == nil || next!.isWhitespace {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                current = ""
            }
        }
        return (sentences, current.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
