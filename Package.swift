// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SAIsWhisper",
    platforms: [.macOS(.v26)],
    // No dependencies: speech is Apple's SpeechTranscriber, which ships with macOS.
    targets: [
        // The dictionary is its own target so it can be tested directly: its behaviour is
        // pinned by the vectors in shared/dictionary-test-vectors.json.
        .target(
            name: "WhisperDictionary",
            path: "Sources/WhisperDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SAIsWhisper",
            dependencies: ["WhisperDictionary"],
            path: "Sources/SAIsWhisper",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "WhisperDictionaryTests",
            dependencies: ["WhisperDictionary"],
            path: "Tests/WhisperDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
