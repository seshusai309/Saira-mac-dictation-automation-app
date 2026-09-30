// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Saira",
    platforms: [.macOS(.v26)],
    // No dependencies: speech is Apple's SpeechTranscriber, which ships with macOS.
    targets: [
        // The dictionary is its own target so it can be tested directly: its behaviour is
        // pinned by the vectors in shared/dictionary-test-vectors.json.
        .target(
            name: "SairaDictionary",
            path: "Sources/SairaDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Saira",
            dependencies: ["SairaDictionary"],
            path: "Sources/Saira",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "SairaDictionaryTests",
            dependencies: ["SairaDictionary"],
            path: "Tests/SairaDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
