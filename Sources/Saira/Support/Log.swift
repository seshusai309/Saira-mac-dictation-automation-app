import OSLog

enum Log {
    static let audio = Logger(subsystem: "ai.sai.whisper", category: "audio")
    static let speech = Logger(subsystem: "ai.sai.whisper", category: "speech")
    static let hotkey = Logger(subsystem: "ai.sai.whisper", category: "hotkey")
    static let inject = Logger(subsystem: "ai.sai.whisper", category: "inject")
    static let app = Logger(subsystem: "ai.sai.whisper", category: "app")
}
