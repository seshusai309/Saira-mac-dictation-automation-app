import WhisperDictionary
import SwiftUI

// The app's shared vocabulary. Every value comes from `DS`; if a component needs a number
// that isn't a token, the token is missing — add it there rather than inlining it.

// MARK: - Surfaces

/// The window's paper: the canvas color plus a faint, fixed speckle of grain.
///
/// The grain is drawn rather than an image, so it stays crisp at any scale and follows the
/// theme. Positions come from a seeded generator, so it doesn't shimmer on redraw.
struct PaperBackground: View {
    var color: Color = DS.Color.canvas

    var body: some View {
        ZStack {
            color
            Canvas { context, size in
                var rng = SeededGenerator(seed: 0x5A1)
                let count = Int(size.width * size.height / 10_000 * DS.Material.grainDensity)
                for _ in 0..<count {
                    let x = CGFloat.random(in: 0..<max(size.width, 1), using: &rng)
                    let y = CGFloat.random(in: 0..<max(size.height, 1), using: &rng)
                    let speck = CGRect(x: x, y: y, width: 1, height: 1)
                    context.fill(Path(speck), with: .color(DS.Color.ink.opacity(DS.Material.grainOpacity)))
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Deterministic randomness for the grain. SplitMix64.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension View {
    /// A card on the canvas: paper-white, hairline edge, soft shadow.
    func cardStyle(radius: CGFloat = DS.Radius.card, fill: Color = DS.Color.card) -> some View {
        // The shadow goes on the background shape, not the container: `.shadow` on a view
        // shadows everything inside it too, which haloes every keycap and line of text.
        self
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
                    .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, y: DS.Shadow.card.y)
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
            )
    }

    /// An inset well: fields, example boxes.
    func sunkenStyle(radius: CGFloat = DS.Radius.control) -> some View {
        self
            .background(DS.Color.sunken, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
            )
    }
}

// MARK: - Type

/// A small uppercase, tracked label. Uppercased here so a label can never be half-styled.
struct Eyebrow: View {
    let text: String
    var color: Color = DS.Color.inkTertiary

    var body: some View {
        Text(text.uppercased())
            .font(DS.Font.eyebrow)
            .tracking(DS.Font.eyebrowTracking)
            .foregroundStyle(color)
    }
}

/// Eyebrow over a serif title whose second half is italic — the editorial header every
/// screen opens with.
struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var italic: String = ""
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Eyebrow(text: eyebrow)
                Text("\(Text(title).font(DS.Font.display))\(Text(italic.isEmpty ? "" : " " + italic).font(DS.Font.displayItalic))")
                    .foregroundStyle(DS.Color.ink)
            }
            Spacer(minLength: DS.Space.roomy)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, italic: String = "") {
        self.init(eyebrow: eyebrow, title: title, italic: italic) { EmptyView() }
    }
}

// MARK: - Keycaps

/// A physical key: a face sitting on a darker skirt, so it reads as something you press.
struct Keycap: View {
    let label: String
    /// The pill draws keycaps on night; everything else on paper.
    var onDark = false

    var body: some View {
        Text(label)
            .font(DS.Font.keycap)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(onDark ? DS.Color.pillInk : DS.Color.ink)
            .padding(.horizontal, DS.Space.snug)
            .frame(minWidth: DS.Size.keycapMinWidth, minHeight: DS.Size.keycapHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.keycap, style: .continuous)
                    .fill(onDark ? DS.Color.pillButton : DS.Color.keycap)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.keycap, style: .continuous)
                    .strokeBorder(onDark ? DS.Color.pillEdge : DS.Color.keycapSkirt, lineWidth: DS.Border.hairline)
            )
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.keycap, style: .continuous)
                    .fill(onDark ? DS.Color.pillEdge : DS.Color.keycapSkirt)
                    .offset(y: DS.Border.keycapDepth)
            )
            .padding(.bottom, DS.Border.keycapDepth)
    }
}

/// A shortcut drawn as its keys.
struct ShortcutKeys: View {
    let shortcut: Shortcut
    var onDark = false

    var body: some View {
        HStack(spacing: DS.Space.tight) {
            ForEach(shortcut.keycaps, id: \.self) { Keycap(label: $0, onDark: onDark) }
        }
    }
}

// MARK: - Buttons

/// Wispr's capsule buttons: lavender primary, outlined secondary, bare quiet.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(kind: kind, configuration: configuration)
    }

    private struct PillButtonBody: View {
        let kind: Kind
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(DS.Font.button)
                .lineLimit(1)
                .padding(.horizontal, kind == .quiet ? DS.Space.snug : DS.Space.roomy)
                .frame(height: DS.Size.buttonHeight)
                .foregroundStyle(foreground)
                .background(Capsule().fill(fill(pressed: pressed)))
                .overlay {
                    if kind == .secondary {
                        Capsule().strokeBorder(DS.Color.ink.opacity(0.85), lineWidth: DS.Border.hairline)
                    }
                }
                .contentShape(Capsule())
                .scaleEffect(pressed ? DS.Motion.pressScale : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(DS.Motion.quick, value: pressed)
        }

        private var foreground: Color {
            switch kind {
            case .primary: DS.Color.onAccent
            case .secondary: DS.Color.ink
            case .quiet: DS.Color.inkSecondary
            }
        }

        private func fill(pressed: Bool) -> Color {
            switch kind {
            case .primary: pressed ? DS.Color.accentPressed : DS.Color.accent
            case .secondary: pressed ? DS.Color.hover : .clear
            case .quiet: pressed ? DS.Color.hover : .clear
            }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillPrimary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pillSecondary: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillQuiet: PillButtonStyle { PillButtonStyle(kind: .quiet) }
}

/// A small round icon button for row actions.
struct IconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? DS.Color.ink : DS.Color.inkTertiary)
                .frame(width: DS.Size.keycapHeight + DS.Space.tight, height: DS.Size.keycapHeight + DS.Space.tight)
                .background(Circle().fill(isHovering ? DS.Color.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Fields

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: DS.Space.snug) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Color.inkTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.Color.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.base)
        .frame(height: DS.Size.fieldHeight)
        .background(DS.Color.sunken, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline))
    }
}

// MARK: - Signals

/// A small colored dot, optionally breathing — the record light, the ready light.
struct StatusDot: View {
    let color: Color
    var pulsing = false
    var size: CGFloat = DS.Size.statusDot

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !pulsing)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate / DS.Motion.pulse * 2 * .pi
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .opacity(pulsing ? 0.55 + 0.45 * (0.5 + 0.5 * sin(phase)) : 1)
        }
        .frame(width: size, height: size)
    }
}

/// A capsule tag.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = DS.Color.inkSecondary
    var fill: Color = DS.Color.hover

    var body: some View {
        HStack(spacing: DS.Space.tight) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text)
        }
        .font(DS.Font.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, DS.Space.snug)
        .padding(.vertical, DS.Space.hair)
        .background(fill, in: Capsule())
    }
}

// MARK: - Instrumentation

/// Level-reactive waveform bars. Each bar has a fixed phase offset so the group ripples
/// instead of pumping in unison.
struct LevelBars: View {
    let level: Float
    var isActive: Bool
    var count: Int = 24
    var maxHeight: CGFloat = 40
    var color: Color = DS.Color.ink

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: DS.Material.barGap) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: DS.Material.barWidth, height: height(for: index, at: t))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        let floor = DS.Material.barFloor
        guard isActive else { return floor }

        // Irrational multiplier keeps the offsets from lining up into a visible period.
        let phase = (Double(index) * 0.618).truncatingRemainder(dividingBy: 1)
        let wave = sin(time * 6.0 + phase * .pi * 2)
        // Center-weighted, so the shape reads as a voice rather than a bar chart.
        let middle = Double(count - 1) / 2
        let envelope = 1 - 0.55 * abs(Double(index) - middle) / max(middle, 1)
        let amplitude = CGFloat(max(0.05, level)) * CGFloat(envelope)
        let scaled = amplitude * (0.55 + 0.45 * CGFloat(wave))
        return floor + max(0, scaled) * (maxHeight - floor)
    }
}

/// A segmented LED meter — the retro level readout. Teal, then amber, then Flare at the top.
struct SegmentMeter: View {
    let level: Float

    var body: some View {
        let lit = Int((Double(min(max(level, 0), 1)) * Double(DS.Material.meterSegments)).rounded())
        HStack(spacing: DS.Material.meterSegmentGap) {
            ForEach(0..<DS.Material.meterSegments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < lit ? color(for: index) : DS.Color.meterOff)
                    .frame(width: DS.Material.meterSegmentWidth, height: DS.Material.meterHeight)
            }
        }
        .animation(DS.Motion.quick, value: lit)
        .accessibilityLabel("Input level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }

    private func color(for index: Int) -> Color {
        let position = Double(index) / Double(DS.Material.meterSegments)
        if position >= DS.Material.meterHighPoint { return DS.Color.meterHigh }
        if position >= DS.Material.meterMidPoint { return DS.Color.meterMid }
        return DS.Color.meterLow
    }
}

// MARK: - Brand

/// The app mark, drawn to match the app icon: a charcoal tile, cream bars, one lavender.
struct AppMark: View {
    var size: CGFloat = DS.Size.iconTile

    private static let bars: [CGFloat] = [0.34, 0.62, 1.0, 0.7, 0.4]

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(DS.Color.pill)
            // Charcoal on a charcoal sidebar vanishes in dark mode without an edge.
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(DS.Color.pillEdge, lineWidth: DS.Border.hairline)
            )
            .overlay {
                HStack(spacing: size * 0.075) {
                    ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, height in
                        Capsule()
                            .fill(index == 2 ? DS.Color.accent : DS.Color.pillInk)
                            .frame(width: size * 0.085, height: size * 0.5 * height)
                    }
                }
            }
            .frame(width: size, height: size)
    }
}

// MARK: - Content

struct EmptyState: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: DS.Space.snug) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(DS.Color.inkTertiary)
            Text(title)
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.ink)
            Text(detail)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shows that the dictionary fired, and on what. Without this the dictionary is invisible
/// and you can't tell a rule that works from one that never matches.
struct CorrectionBadges: View {
    let corrections: [AppliedCorrection]

    var body: some View {
        HStack(spacing: DS.Space.tight) {
            ForEach(corrections, id: \.self) { correction in
                HStack(spacing: DS.Space.tight) {
                    Text(correction.from)
                        .strikethrough()
                        .foregroundStyle(DS.Color.inkTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DS.Color.inkTertiary)
                    Text(correction.to)
                        .foregroundStyle(DS.Color.live)
                    if correction.count > 1 {
                        Text("×\(correction.count)").foregroundStyle(DS.Color.inkTertiary)
                    }
                }
                .font(DS.Font.caption)
                .padding(.horizontal, DS.Space.snug)
                .padding(.vertical, DS.Space.hair)
                .background(DS.Color.liveSoft, in: Capsule())
            }
        }
    }
}

/// A row in a settings card: title and explanation on the left, control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.roomy) {
            VStack(alignment: .leading, spacing: DS.Space.hair) {
                Text(title)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.ink)
                if let detail {
                    Text(detail)
                        .font(DS.Font.label)
                        .foregroundStyle(DS.Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.base)
            control
        }
        .padding(.vertical, DS.Space.snug)
    }
}

// MARK: - Formatting

enum Formatters {
    /// "Today, 3:24 PM" / "Yesterday, 6:45 PM" / "Sep 14, 2:10 PM".
    static func relative(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today, \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day()) + ", " + time
    }

    static func seconds(_ value: Double) -> String {
        String(format: "%.1fs", value)
    }

    /// "00:07" — a tape counter.
    static func counter(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
