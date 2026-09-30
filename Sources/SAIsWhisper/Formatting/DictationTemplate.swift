import Foundation

/// How cleanup shapes what you said, chosen for where the words are going.
///
/// A template is *extra rules on top of* cleanup, never a different kind of processing: the
/// on-device model gets a few more lines of instruction, and the rule-based fallback flips a
/// couple of switches. It never licenses the model to add content — the plausibility guard in
/// `FoundationModelFormatter` applies to every template equally.
enum DictationTemplate: String, CaseIterable, Identifiable, Sendable {
    case everyday
    case notes
    case code
    case content
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyday: "Everyday"
        case .notes: "Notes"
        case .code: "Code"
        case .content: "Content"
        case .tasks: "Tasks"
        }
    }

    var symbol: String {
        switch self {
        case .everyday: "text.bubble"
        case .notes: "note.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .content: "pencil.line"
        case .tasks: "checklist"
        }
    }

    var summary: String {
        switch self {
        case .everyday: "Clean sentences for anywhere you type — chat, search, forms."
        case .notes: "Capture thoughts fast. Short paragraphs, a light touch."
        case .code: "Identifiers, commands and prompts, without prose punctuation."
        case .content: "Emails, posts and documents, with proper paragraphs."
        case .tasks: "A spoken to-do list becomes a checklist."
        }
    }

    /// A before/after pair for the Templates screen.
    var example: (said: String, result: String) {
        switch self {
        case .everyday:
            ("um so can you send me the file when you get a chance",
             "Can you send me the file when you get a chance?")
        case .notes:
            ("idea for the talk uh open with the demo then the numbers",
             "Idea for the talk: open with the demo, then the numbers.")
        case .code:
            ("run npm install then npm run dev",
             "run npm install then npm run dev")
        case .content:
            ("hi sarah new paragraph thanks for the notes I'll send the draft friday",
             "Hi Sarah,\n\nThanks for the notes. I'll send the draft Friday.")
        case .tasks:
            ("buy milk call the bank and book the flights",
             "- Buy milk\n- Call the bank\n- Book the flights")
        }
    }

    /// Whether this template needs the on-device model to do what it says. The rule-based
    /// pass can't restructure a sentence into a list.
    var needsSmartCleanup: Bool { self == .tasks || self == .content }

    /// Appended to the cleanup model's instructions.
    var instructions: String {
        switch self {
        case .everyday:
            return ""
        case .notes:
            return """
                - The text is a quick personal note. Keep it terse; prefer short sentences and \
                short paragraphs. Do not add headings.
                """
        case .code:
            return """
                - The text is going into a code editor, terminal or AI prompt. Keep technical \
                terms, commands, file names and identifiers exactly as spoken. Do not add a \
                trailing period and do not capitalize the first word of a command.
                """
        case .content:
            return """
                - The text is an email, post or document. Use proper paragraphs. If the speaker \
                opens with a greeting, put it on its own line followed by a blank line.
                """
        case .tasks:
            return """
                - The text is a to-do list. Put each separate task on its own line starting \
                with "- ". Capitalize each task. No trailing periods.
                """
        }
    }

    /// Rule-based cleanup: capitalize sentence starts.
    var capitalizes: Bool { self != .code }

    /// Rule-based cleanup: end with a full stop if the speaker didn't.
    var addsTerminalPunctuation: Bool { self != .code && self != .tasks }
}
