#if DEBUG
import AppKit
import SwiftUI

/// Renders every screen, in both themes, to PNGs — for reviewing the design without Screen
/// Recording permission, which a screenshot tool would need.
///
/// Debug builds only. Run the binary with a folder to write into:
///
/// ```bash
/// SAIRA_SNAPSHOT_DIR=/tmp/shots "…/Saira.app/Contents/MacOS/Saira"
/// ```
///
/// It draws views in-process with `cacheDisplay`, so AppKit-backed controls (fields, switches,
/// pickers) render for real — unlike `ImageRenderer`, which leaves them blank. It quits when
/// done, and never arms the shortcut or asks for permissions.
@MainActor
enum DesignSnapshots {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["SAIRA_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(controller: DictationController) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        Task { @MainActor in
            // Wait for the main window — it can take a moment on a cold launch.
            var mainWindow: NSWindow?
            for _ in 0..<20 where mainWindow == nil {
                try? await Task.sleep(for: .milliseconds(300))
                mainWindow = NSApp.windows.first { $0.identifier?.rawValue == "main" }
            }
            guard let window = mainWindow, let view = window.contentView else {
                let found = NSApp.windows.map { "\($0.identifier?.rawValue ?? "nil")/\($0.title)/\($0.isVisible)" }
                Log.app.error("snapshots: no main window among \(found, privacy: .public)")
                exit(1)
            }
            window.makeKeyAndOrderFront(nil)
            window.setContentSize(NSSize(width: 1080, height: 720))

            for theme in [AppTheme.light, .dark] {
                NSApp.appearance = theme.appearance

                for section in AppNavigation.Section.allCases {
                    AppNavigation.shared.section = section
                    await settle()
                    save(view, "\(theme.rawValue)-\(section.rawValue)")
                }

                AppNavigation.shared.section = .dictate
                controller.clearResult()
                await settle()
                save(view, "\(theme.rawValue)-dictate-ready")

                controller.debugSimulate(
                    .listening,
                    transcript: "I need to finish the AI project architecture today and then continue working on the RAG pipeline",
                    level: 0.7
                )
                await settle()
                save(view, "\(theme.rawValue)-dictate-listening")

                controller.debugSimulate(.finishing)
                await settle()
                save(view, "\(theme.rawValue)-dictate-transcribing")

                controller.debugSimulate(.idle)
                controller.show(sample)
                await settle()
                save(view, "\(theme.rawValue)-dictate-result")
                controller.clearResult()
            }

            // The pill is always night, so one pass over its states covers both themes.
            let phases: [(String, FlowPill.Phase, Bool)] = [
                ("idle", .idle, false),
                ("idle-hover", .idle, true),
                ("listening", .listening, false),
                ("transcribing", .transcribing, false),
                ("copied", .done(.copied), false),
                ("error", .error("Microphone access is off. Turn it on in System Settings."), false),
            ]
            controller.debugSimulate(.listening, transcript: "and then continue working on the RAG pipeline", level: 0.7)
            for (name, phase, hover) in phases {
                let host = NSHostingView(rootView: ZStack {
                    desktop
                    FlowPill(controller: controller, phaseOverride: phase, hoverOverride: hover)
                })
                host.frame = CGRect(origin: .zero, size: DS.Size.pillCanvas)
                let holder = NSWindow(
                    contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false
                )
                holder.contentView = host
                await settle()
                save(host, "pill-\(name)")
            }
            controller.debugSimulate(.idle)

            await filmBubbleEntry(controller: controller)

            Log.app.info("snapshots written to \(directory.path, privacy: .public)")
            exit(0)
        }
    }

    /// Frames of the live pill from the moment it's triggered, with a simulated voice — the
    /// only way to review motion (pop, stretch, rising bubbles) rather than a single pose.
    /// The window has to be on screen for the animations to run, so this briefly shows one.
    private static func filmBubbleEntry(controller: DictationController) async {
        let host = NSHostingView(rootView: ZStack {
            desktop
            FlowPill(controller: controller)
        })
        host.frame = CGRect(origin: .zero, size: DS.Size.pillCanvas)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.level = .floating
        window.orderFrontRegardless()
        await settle()

        let words = "I need to finish the project today and then keep working on the pipeline"
            .split(separator: " ")
        let start = ContinuousClock.now
        let captures: [Int] = [40, 90, 150, 240, 400, 700, 1100, 1600]  // ms after the trigger
        var next = 0
        var frame = 0
        controller.debugSimulate(.listening, transcript: "", level: 0.5)
        while next < captures.count {
            let elapsed = Int((ContinuousClock.now - start) / .milliseconds(1))
            // A voice that rises and falls, adding a word every ~120 ms.
            let level = Float(0.45 + 0.4 * sin(Double(elapsed) / 170))
            let spoken = words.prefix(min(words.count, elapsed / 120)).joined(separator: " ")
            controller.debugSimulate(.listening, transcript: spoken, level: level)
            if elapsed >= captures[next] {
                save(host, String(format: "anim-%02d-%04dms", frame, captures[next]))
                next += 1
                frame += 1
            }
            try? await Task.sleep(for: .milliseconds(16))
        }
        window.orderOut(nil)
        controller.debugSimulate(.idle)
    }

    /// A stand-in desktop behind the pill: color and a few hard edges, so glass translucency
    /// and the rim are judged against something busy rather than flat grey.
    private static var desktop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.30, blue: 0.52), Color(red: 0.78, green: 0.44, blue: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(spacing: 40) {
                ForEach(0..<6, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(index.isMultiple(of: 2) ? 0.55 : 0.18))
                        .frame(width: 50, height: 260)
                        .rotationEffect(.degrees(18))
                }
            }
        }
    }

    private static let sample = DictationRun(
        date: .now,
        engine: "Apple",
        audioSeconds: 6.2,
        processSeconds: 0.8,
        text: "I need to finish the AI project architecture today and then continue working on the RAG pipeline.",
        corrections: [AppliedCorrectionSample.claudeCode],
        template: DictationTemplate.everyday.rawValue
    )

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(700))
    }

    private static func save(_ view: NSView, _ name: String) {
        view.layoutSubtreeIfNeeded()
        guard let directory, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}

import SairaDictionary

private enum AppliedCorrectionSample {
    /// `AppliedCorrection` has no public memberwise init, so decode one.
    static var claudeCode: AppliedCorrection {
        let json = #"{"from":"cloud code","to":"Claude Code","count":1}"#
        return try! JSONDecoder().decode(AppliedCorrection.self, from: Data(json.utf8))
    }
}
#endif

#if DEBUG
/// Drives the real `PillPresenter` through two dictations and reports what happened: a fresh
/// window per dictation, on screen while listening, gone afterwards — plus an image of what
/// the first window actually drew. Debug builds only:
///
/// ```bash
/// SAIRA_PILL_SELFTEST=/tmp/pilltest "…/Saira.app/Contents/MacOS/Saira"
/// ```
@MainActor
enum PillSelfTest {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["SAIRA_PILL_SELFTEST"].map { URL(fileURLWithPath: $0) }
    }

    static func run(controller: DictationController) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var report: [String] = []

        func pillWindows() -> [HUDPanel] { NSApp.windows.compactMap { $0 as? HUDPanel } }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            var identities: [ObjectIdentifier] = []

            for round in 1...2 {
                controller.debugSimulate(.listening, transcript: "hello", level: 0.6)
                try? await Task.sleep(for: .milliseconds(1_300))
                let visible = pillWindows().filter(\.isVisible)
                let onScreen = visible.first?.occlusionState.contains(.visible) ?? false
                report.append("round \(round): visible pill windows = \(visible.count), macOS says on screen = \(onScreen)")
                if let panel = visible.first {
                    identities.append(ObjectIdentifier(panel))
                    if round == 1, let view = panel.contentView,
                       let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?
                            .write(to: directory.appendingPathComponent("pill-live.png"))
                    }
                }
                controller.debugSimulate(.idle)
                try? await Task.sleep(for: .milliseconds(900))
                report.append("round \(round): visible pill windows after finishing = \(pillWindows().filter(\.isVisible).count)")
            }
            report.append("fresh window each dictation = \(identities.count == 2 && identities[0] != identities[1])")
            try? report.joined(separator: "\n").write(
                to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8
            )
            exit(0)
        }
    }
}
#endif
