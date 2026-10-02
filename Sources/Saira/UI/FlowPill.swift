import AppKit
import SwiftUI

/// The floating pill at the bottom of the screen.
///
/// Dark frosted glass with one warm signal color, amber:
///
/// `( ▂▅█▅▂ │ Saira )`
///
/// Small, and only two things: your voice as amber bars, fading at the ends, and the app's
/// name. No icon, no timer, no status words, nothing that spins — a turning ring reads as a
/// loading spinner, the opposite of "go ahead, I'm listening".
///
/// **Instant in, instant out.** It appears fully formed the moment a hold engages (120 ms) and
/// is gone the moment you let go — no pop, no stretch, no fade, by request. The only motion is
/// the voice itself: `VoiceRibbon` draws the last half-second of your actual loudness, ~100
/// samples a second, scrolling through the pill, so every word and pause is visible.
///
/// Optional bubbles rising off it remain in Settings (off by default).
struct FlowPill: View {
    @Bindable var controller: DictationController
    /// Pins the pill to one state — design snapshots only; nil in the app.
    var phaseOverride: Phase?
    /// Pins the idle pill open, as if hovered — design snapshots only.
    var hoverOverride = false

    @State private var settings = Settings.shared
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsHover: Bool { isHovering || hoverOverride }

    enum Phase: Equatable {
        case hidden
        case idle
        case listening
        case transcribing
        case done(DictationController.Delivery)
        case error(String)
    }

    var phase: Phase {
        if let phaseOverride { return phaseOverride }
        switch controller.state {
        case .starting, .listening:
            // Not until the hold is long enough to be deliberate.
            return controller.isEngaged ? .listening : .hidden
        // Gone the moment you let go — the text arriving is the feedback.
        case .finishing: return .hidden
        case .error(let message): return .error(message)
        case .idle:
            if let delivery = controller.delivery { return .done(delivery) }
            return settings.showIdlePill ? .idle : .hidden
        }
    }

    /// The states drawn as the full pill.
    private var isWorking: Bool {
        switch phase {
        case .listening, .transcribing, .done, .error: true
        case .hidden, .idle: false
        }
    }

    /// Optional bubbles, while talking — and through transcribing, so the ones already in the
    /// air can finish rising instead of vanishing mid-flight.
    private var showsBubbles: Bool {
        settings.voiceBubbles && !reduceMotion && (phase == .listening || phase == .transcribing)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if showsBubbles {
                BubbleStream(
                    level: controller.level,
                    wordCount: wordCount,
                    isEmitting: phase == .listening,
                    prefill: phaseOverride != nil
                )
                .padding(.bottom, DS.Size.pillBottomMargin + DS.Size.pillHeight * 0.6)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            VStack {
                Spacer(minLength: 0)
                if isWorking {
                    workingPill
                } else if phase == .idle {
                    idlePill
                }
            }
            .padding(.bottom, DS.Size.pillBottomMargin)
        }
        .frame(width: DS.Size.pillCanvas.width, height: DS.Size.pillCanvas.height)
        .animation(DS.Motion.quick, value: isHovering)
        // No transaction animation for phase changes: in and out are instant.
        .transaction { $0.animation = nil }
    }

    private var wordCount: Int {
        controller.transcript.split(whereSeparator: \.isWhitespace).count
    }

    // MARK: - The pill

    private var workingPill: some View {
        content
            .padding(.horizontal, DS.Space.roomy)
            .frame(minWidth: DS.Size.pillMinWidth, minHeight: DS.Size.pillHeight)
            .fixedSize()
            .background { GlassCapsule() }
            .contentShape(Capsule())
            .onTapGesture {
                // Started with a click, so it finishes with one. A held key finishes on release.
                if phase == .listening, controller.isHandsFree, controller.source != .shortcut {
                    controller.stop()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .listening:
            HStack(spacing: DS.Space.base) {
                VoiceRibbon(meter: controller.meter, frozen: phaseOverride != nil)
                divider
                name
            }

        case .transcribing:
            HStack(spacing: DS.Space.base) {
                TravellingDots()
                    // Same footprint as the bars, so the pill doesn't jump when you let go.
                    .frame(width: DS.Size.pillBarsWidth)
                divider
                name
            }

        case .done(let delivery):
            HStack(spacing: DS.Space.snug) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Color.amber)
                Text(message(for: delivery))
                    .font(DS.Font.pillHint)
                    .foregroundStyle(DS.Color.pillInk)
                    .fixedSize()
            }

        case .error(let message):
            HStack(spacing: DS.Space.snug) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.meterMid)
                Text(message)
                    .font(DS.Font.pillHint)
                    .foregroundStyle(DS.Color.pillInk)
                    .lineLimit(2)
                    .frame(maxWidth: DS.Size.pillTextMaxWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .hidden, .idle:
            EmptyView()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Color.pillDivider)
            .frame(width: DS.Border.hairline, height: DS.Size.pillDividerHeight)
    }

    private var name: some View {
        Text("Saira")
            .font(DS.Font.pillName)
            .foregroundStyle(DS.Color.pillInk)
            .fixedSize()
    }

    private func message(for delivery: DictationController.Delivery) -> String {
        switch delivery {
        case .copied: "Copied — paste with ⌘V"
        }
    }

    // MARK: - Idle

    /// Only when "Show the pill when idle" is on: a tiny capsule of dots you can click.
    private var idlePill: some View {
        Group {
            if showsHover {
                HStack(spacing: DS.Space.snug) {
                    Text(settings.activationMode == .hold ? "Hold" : "Press")
                        .foregroundStyle(DS.Color.pillTextDim)
                    ShortcutKeys(shortcut: settings.shortcut, onDark: true)
                    Text("or click to dictate")
                        .foregroundStyle(DS.Color.pillTextDim)
                }
                .font(DS.Font.pill)
                .padding(.horizontal, DS.Space.base)
                .frame(minHeight: DS.Size.pillButton + DS.Space.base)
            } else {
                HStack(spacing: DS.Space.tight) {
                    ForEach(0..<6, id: \.self) { _ in
                        Circle()
                            .fill(DS.Color.pillTextDim)
                            .frame(width: 2.5, height: 2.5)
                    }
                }
                .frame(minWidth: DS.Size.pillIdle.width, minHeight: DS.Size.pillIdle.height)
            }
        }
        .fixedSize()
        .background { GlassCapsule() }
        .contentShape(Capsule())
        .onHover { isHovering = $0 }
        .onTapGesture { controller.togglePill() }
    }
}

// MARK: - Glass

/// The pill's body: a blur of what's behind with only a light dark tint, so the screen shows
/// through; a sheen across the top half; and an edge that catches the light at the top and
/// fades toward the bottom — glass, not a flat black slab.
private struct GlassCapsule: View {
    var body: some View {
        ZStack {
            BehindWindowBlur()
            Capsule().fill(DS.Color.pillGlass)
            Capsule().fill(
                LinearGradient(
                    colors: [DS.Color.pillSheen, .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.6)
                )
            )
        }
        .environment(\.colorScheme, .dark)
        // The glass edge: light catching the top, fading down — then a fainter inner edge
        // that reads as the glass's thickness.
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [DS.Color.pillRimTop, DS.Color.pillRimBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: DS.Border.hairline
            )
        )
        .overlay(
            Capsule()
                .strokeBorder(DS.Color.pillInnerRim, lineWidth: DS.Border.hairline)
                .padding(DS.Border.hairline + 0.5)
        )
        .shadow(color: DS.Shadow.pill.color, radius: DS.Shadow.pill.radius, y: DS.Shadow.pill.y)
        .shadow(color: DS.Shadow.pillHalo.color, radius: DS.Shadow.pillHalo.radius)
    }
}

/// A real blur of the desktop *behind* the pill's window, cut to a capsule.
///
/// SwiftUI's `.ultraThinMaterial` doesn't promise behind-window blending in a borderless
/// floating panel; `NSVisualEffectView` with `.behindWindow` does — it's what HUD windows use.
/// Its shape comes from a mask image rebuilt whenever the height changes, because SwiftUI
/// clipping isn't reliably applied to a hosted AppKit view.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> CapsuleEffectView {
        let view = CapsuleEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: CapsuleEffectView, context: Context) {}

    final class CapsuleEffectView: NSVisualEffectView {
        private var maskedHeight: CGFloat = 0

        override func layout() {
            super.layout()
            let height = bounds.height
            guard height > 0, height != maskedHeight else { return }
            maskedHeight = height
            let radius = height / 2
            let image = NSImage(size: NSSize(width: height, height: height), flipped: false) { rect in
                NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
                return true
            }
            // Stretches the middle, keeps the round ends — one image fits any width.
            image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
            image.resizingMode = .stretch
            maskImage = image
        }
    }
}

// MARK: - Voice ribbon

/// Your voice, live and smooth: bars that stay in place and *glide* to your loudness.
///
/// The first version scrolled a bar per ~30 ms of audio, and the discrete step read as stutter.
/// Now every frame each bar eases toward a target with a time-based exponential (so it's
/// equally smooth at 60 Hz and 120 Hz): fast attack (~40 ms) so a word lifts the bars at once,
/// soft release (~150 ms) so a pause settles instead of snapping. Each bar sways at its own
/// slow rhythm scaled by loudness — still and flat in silence, a flowing wave while you talk,
/// tallest in the middle.
///
/// Drawn in one `Canvas` from `LevelMeter`, which the audio thread writes; nothing here goes
/// through SwiftUI state, so audio never re-runs the view tree.
private struct VoiceRibbon: View {
    let meter: LevelMeter
    /// Design snapshots: draw a fixed shape, since an offscreen snapshot has no audio.
    var frozen = false

    /// Per-frame motion state. A plain reference, deliberately not `@State`: it's stepped
    /// inside the draw closure, where mutating SwiftUI state is a mutation during update.
    @State private var motion = Motion()

    private final class Motion {
        var heights = [Double](repeating: 0, count: DS.Size.pillBars)
        var level = 0.0
        var lastFrame: Double?
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            // The frame time must be an input to the drawing, or SwiftUI never redraws it.
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let heights = frozen ? Self.sample : step(to: now)
                let pitch = DS.Material.barWidth + DS.Material.barGap
                let midY = size.height / 2
                for (index, value) in heights.enumerated() {
                    let height = max(DS.Material.barFloor, CGFloat(value) * size.height)
                    let bar = CGRect(
                        x: CGFloat(index) * pitch, y: midY - height / 2,
                        width: DS.Material.barWidth, height: height
                    )
                    // Warmer and more opaque as it rises; pale and soft at rest.
                    let tint = DS.Color.amberPale.mix(with: DS.Color.amber, by: min(1, value * 1.6))
                    context.fill(
                        Path(roundedRect: bar, cornerRadius: DS.Material.barWidth / 2),
                        with: .color(tint.opacity(0.45 + 0.55 * min(1, value * 1.4)))
                    )
                }
            }
        }
        .frame(width: DS.Size.pillBarsWidth, height: DS.Size.pillBarsHeight)
    }

    /// Advances the motion to `now` and returns each bar's height, 0…1.
    private func step(to now: Double) -> [Double] {
        let dt = min(max(now - (motion.lastFrame ?? now), 0), 1.0 / 20)
        motion.lastFrame = now

        // Loudness: the peak of the last ~30 ms, eased — quick up, gentle down.
        let target = Double(meter.recent(3).max() ?? 0)
        let tau = target > motion.level ? DS.Motion.voiceAttack : DS.Motion.voiceRelease
        motion.level += (target - motion.level) * (1 - exp(-dt / tau))
        let level = pow(motion.level, 0.85)

        let count = motion.heights.count
        let middle = Double(count - 1) / 2
        for index in 0..<count {
            // Tallest in the middle, tapering to the ends.
            let envelope = 1 - 0.6 * pow(abs(Double(index) - middle) / middle, 1.6)
            // A slow sway unique to each bar; it only shows when there's voice behind it.
            let rate = 5.0 + Double(index % 5) * 1.3
            let phase = Double(index) * 1.7
            let sway = 0.62 + 0.38 * sin(now * rate + phase)
            let goal = min(1, level * envelope * sway * 1.2)
            let barTau = goal > motion.heights[index] ? DS.Motion.voiceAttack : DS.Motion.voiceRelease
            motion.heights[index] += (goal - motion.heights[index]) * (1 - exp(-dt / barTau))
        }
        return motion.heights
    }

    private static let sample: [Double] = (0..<DS.Size.pillBars).map { index in
        let middle = Double(DS.Size.pillBars - 1) / 2
        return 0.75 * (1 - 0.6 * abs(Double(index) - middle) / middle) * (0.65 + 0.35 * sin(Double(index) * 1.7))
    }
}

// MARK: - Bubbles

/// Bubbles rising off the pill, driven by your voice. Optional — Settings ▸ Voice bubbles.
///
/// Drawn in one `Canvas` at display rate. The particles live in a plain reference type held by
/// the view, deliberately *not* in `@State` values: they advance every frame inside the draw
/// closure, and mutating SwiftUI state there is a mutation during view update — undefined
/// behavior that floods the log at 60–120 fps. A reference the view merely holds is invisible
/// to the state graph, so stepping it is safe.
private struct BubbleStream: View {
    let level: Float
    let wordCount: Int
    let isEmitting: Bool
    /// Design snapshots: start with bubbles already in the air, since an offscreen snapshot
    /// never lets the timeline run.
    var prefill = false

    @State private var field = BubbleField()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                if prefill { field.prefill(size: size, now: now) }
                field.step(
                    now: now,
                    level: isEmitting ? Double(level) : 0,
                    words: wordCount,
                    emitting: isEmitting,
                    size: size
                )
                field.draw(in: &context, now: now)
            }
        }
    }
}

private final class BubbleField {
    struct Bubble {
        var x: Double
        var y: Double
        let radius: Double
        let speed: Double
        let sway: Double
        let swayPhase: Double
        let born: Double
        let life: Double
        let isWord: Bool
    }

    private var bubbles: [Bubble] = []
    private var lastStep: Double?
    private var spawnDebt = 0.0
    private var lastWords = 0
    private var didPrefill = false

    func step(now: Double, level: Double, words: Int, emitting: Bool, size: CGSize) {
        // Clamped so a stalled frame doesn't teleport every bubble at once.
        let dt = max(0, min(now - (lastStep ?? now), 1.0 / 20))
        lastStep = now

        if emitting {
            // Voice level → how many bubbles and how big. Curved, so quiet speech stays a
            // gentle trickle and only real volume turns it into a stream.
            let loudness = pow(max(0, min(1, level)), 1.3)
            let rate = DS.Material.bubbleRateQuiet
                + (DS.Material.bubbleRateLoud - DS.Material.bubbleRateQuiet) * loudness
            spawnDebt += rate * dt
            while spawnDebt >= 1 {
                spawnDebt -= 1
                spawn(isWord: false, loudness: loudness, now: now, size: size)
            }

            // One bigger bubble for each word the engine adds.
            if words > lastWords {
                for _ in 0..<min(words - lastWords, 3) {
                    spawn(isWord: true, loudness: loudness, now: now, size: size)
                }
            }
        }
        lastWords = words

        for index in bubbles.indices {
            bubbles[index].y -= bubbles[index].speed * dt
        }
        bubbles.removeAll { now - $0.born > $0.life || $0.y < -$0.radius * 2 }
    }

    func draw(in context: inout GraphicsContext, now: Double) {
        for bubble in bubbles {
            let age = now - bubble.born
            let t = age / bubble.life
            // Quick fade in, long fade out.
            let alpha = min(1, age / 0.18) * pow(max(0, 1 - t), 1.2)
            guard alpha > 0.01 else { continue }

            let radius = bubble.radius * (1 + 0.3 * t)   // bubbles swell as they rise
            let x = bubble.x + sin(age * 2.6 + bubble.swayPhase) * bubble.sway
            let rect = CGRect(x: x - radius, y: bubble.y - radius, width: radius * 2, height: radius * 2)
            let circle = Path(ellipseIn: rect)
            let tint = bubble.isWord ? DS.Color.amber : DS.Color.pillInk

            // A faint dark rim so pale bubbles still read over a white window.
            context.stroke(circle, with: .color(DS.Color.pill.opacity(0.35 * alpha)), lineWidth: 2)
            context.fill(circle, with: .color(tint.opacity((bubble.isWord ? 0.3 : 0.14) * alpha)))
            context.stroke(circle, with: .color(tint.opacity(0.9 * alpha)), lineWidth: bubble.isWord ? 1.4 : 1)

            // The glint, upper left.
            if radius > 2.5 {
                let glint = radius * 0.3
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: x - radius * 0.45, y: bubble.y - radius * 0.5, width: glint, height: glint
                    )),
                    with: .color(DS.Color.pillInk.opacity(0.75 * alpha))
                )
            }
        }
    }

    /// Snapshots only: run the simulation forward so there's something to see.
    func prefill(size: CGSize, now: Double) {
        guard !didPrefill else { return }
        didPrefill = true
        let frames = 90
        for frame in 0..<frames {
            let time = now - Double(frames - frame) / 60
            step(now: time, level: 0.7, words: frame / 12, emitting: true, size: size)
        }
    }

    private func spawn(isWord: Bool, loudness: Double, now: Double, size: CGSize) {
        guard bubbles.count < DS.Material.bubbleCap else { return }
        let range = isWord ? DS.Material.wordBubbleRadius : DS.Material.bubbleRadius
        // Louder voice, bigger bubbles — within the range.
        let radius = isWord
            ? Double.random(in: range)
            : range.lowerBound + (range.upperBound - range.lowerBound)
                * min(1, 0.25 + loudness * Double.random(in: 0.5...1.0))
        bubbles.append(Bubble(
            x: size.width / 2 + Double.random(in: -DS.Material.bubbleSpread...DS.Material.bubbleSpread),
            y: size.height - Double.random(in: 0...6),
            radius: radius,
            speed: Double.random(in: DS.Material.bubbleSpeed) * (isWord ? 0.8 : 1),
            sway: Double.random(in: DS.Material.bubbleSway),
            swayPhase: Double.random(in: 0...(2 * .pi)),
            born: now,
            life: Double.random(in: DS.Material.bubbleLife),
            isWord: isWord
        ))
    }
}

/// Three amber dots with a highlight travelling across them — "working on it".
private struct TravellingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: DS.Space.snug) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = 0.5 + 0.5 * sin(t * 5 - Double(index) * 0.9)
                    Circle()
                        .fill(DS.Color.amber)
                        .frame(width: 4.5, height: 4.5)
                        .opacity(0.3 + 0.7 * wave)
                        .offset(y: -1.5 * wave)
                }
            }
            .frame(height: DS.Size.pillBarsHeight)
        }
    }
}
