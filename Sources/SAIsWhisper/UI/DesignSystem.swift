import SwiftUI

/// The design system for SAI's Whisper — the retro edition.
///
/// Direction: warm, editorial, a little analogue. The palette is Wispr Flow's own brand set,
/// taken from their site's stylesheet — Lumen cream `#FFFFEB`, Vast charcoal `#1A1A1A`, Dawn
/// lavender `#F0D7FF`, Fathom teal `#034F46`, Flare `#FF6C4C`, Glow `#FFA946`. The retro edition
/// is what's layered on top: paper grain, a serif display face, real keycaps, a mono tape
/// counter, and a segmented LED level meter.
///
/// Every value a view needs lives here; components never declare their own colors, sizes,
/// radii or durations. If a view needs a number that isn't a token, add the token.
///
/// The rules that keep it coherent:
/// - **Flare means recording.** The record dot is the only Flare in the app.
/// - **Lavender is for action and selection** — primary buttons, the active item. Never
///   for text on cream; `accentInk` is the readable violet.
/// - **Teal means live or done** — listening, transcribed, a correction that fired.
/// - **The flow pill is always night**, in both themes, the way Wispr's flow bar is: it
///   floats over other apps and has to read against anything.
enum DS {

    // MARK: - Color

    enum Color {
        // Surfaces — paper by day, charcoal by night.
        /// The window's base. Lumen cream / Vast charcoal.
        static let canvas = dynamic(light: 0xFFFFEB, dark: 0x1A1A1A)
        /// The sidebar, a shade off the canvas.
        static let sidebar = dynamic(light: 0xF7F6DF, dark: 0x151514)
        /// Cards sitting on the canvas.
        static let card = dynamic(light: 0xFFFFF8, dark: 0x222220)
        /// Inset surfaces — fields, wells, example boxes.
        static let sunken = dynamic(light: 0xF3F2DA, dark: 0x181817)
        /// Hairline borders. Lumen-dark by day.
        static let border = dynamic(light: 0xE4E4D0, dark: 0x34342F)
        /// A border that has to be noticed — focused fields, selected tiles.
        static let borderStrong = dynamic(light: 0xC9C9B2, dark: 0x4C4C45)

        // Ink
        static let ink = dynamic(light: 0x1A1A1A, dark: 0xFFFFEB)
        static let inkSecondary = dynamic(light: 0x55554D, dark: 0xBDBDAB)
        static let inkTertiary = dynamic(light: 0x86867A, dark: 0x85857A)

        // Accent — Dawn lavender
        /// Fills for primary buttons and the selected item.
        static let accent = dynamic(light: 0xF0D7FF, dark: 0xF0D7FF)
        /// Hover / pressed lavender.
        static let accentPressed = dynamic(light: 0xE4C3F8, dark: 0xDFC0F4)
        /// Ink on a lavender fill. Always charcoal — lavender is light in both themes.
        static let onAccent = dynamic(light: 0x1A1A1A, dark: 0x1A1A1A)
        /// Readable violet for text and icons on the canvas.
        static let accentInk = dynamic(light: 0x6B3FA0, dark: 0xD9B8F5)
        /// Selected sidebar row — lavender by day, a violet-tinted charcoal by night.
        static let selection = dynamic(light: 0xF0D7FF, dark: 0x3A3046)
        /// Ink on `selection` — charcoal on lavender by day, cream on violet-charcoal by night.
        static let onSelection = dynamic(light: 0x1A1A1A, dark: 0xFFFFEB)
        /// Pointer-over tint for rows.
        static let hover = dynamic(light: 0x1A1A1A, dark: 0xFFFFEB, alpha: 0.045)

        // Signals
        /// Fathom teal: listening, transcribed, corrections that fired.
        static let live = dynamic(light: 0x034F46, dark: 0x6FC7B5)
        static let liveSoft = dynamic(light: 0x034F46, dark: 0x6FC7B5, alpha: 0.12)
        /// Flare: the record dot. Nothing else.
        static let record = dynamic(light: 0xFF6C4C, dark: 0xFF6C4C)
        /// Glow amber: warnings. Darkened by day so it reads on cream.
        static let warning = dynamic(light: 0x9A5700, dark: 0xFFA946)
        static let warningSoft = dynamic(light: 0xFFA946, dark: 0xFFA946, alpha: 0.16)

        // The flow pill — always night.
        static let pill = dynamic(light: 0x1A1A1A, dark: 0x111111)
        static let pillEdge = dynamic(light: 0xFFFFEB, dark: 0xFFFFEB, alpha: 0.14)
        static let pillInk = dynamic(light: 0xFFFFEB, dark: 0xFFFFEB)
        static let pillInkDim = dynamic(light: 0xFFFFEB, dark: 0xFFFFEB, alpha: 0.42)
        static let pillButton = dynamic(light: 0xFFFFEB, dark: 0xFFFFEB, alpha: 0.12)

        // The flow pill — dark frosted glass with an amber signal
        /// The glass body. Translucent, over a blur of whatever's behind it.
        static let pillGlass = dynamic(light: 0x1C1C1F, dark: 0x1C1C1F, alpha: 0.42)
        /// The glass edge: bright where the light catches the top, fading toward the bottom.
        static let pillRimTop = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.42)
        static let pillRimBottom = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.08)
        /// A second, fainter edge just inside the first — the thickness of the glass.
        static let pillInnerRim = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.06)
        /// Top-edge sheen, fading downward.
        static let pillSheen = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.20)
        /// Hairline dividers between the pill's sections.
        static let pillDivider = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.12)
        /// Amber — Wispr's Glow — for the ring and the voice bars. The pill's one color.
        static let amber = dynamic(light: 0xFFA946, dark: 0xFFA946)
        /// The pale end of the amber bars.
        static let amberPale = dynamic(light: 0xFFE7C4, dark: 0xFFE7C4)
        /// Secondary text on the glass.
        static let pillTextDim = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, alpha: 0.55)

        // Keycaps
        static let keycap = dynamic(light: 0xFFFFFF, dark: 0x2E2E2B)
        /// The keycap's lower lip — what makes it read as a key and not a label.
        static let keycapSkirt = dynamic(light: 0xCFCFB8, dark: 0x0C0C0B)

        // LED meter segments, lit
        static let meterLow = dynamic(light: 0x034F46, dark: 0x6FC7B5)
        static let meterMid = dynamic(light: 0xE08A1E, dark: 0xFFA946)
        static let meterHigh = dynamic(light: 0xFF6C4C, dark: 0xFF6C4C)
        static let meterOff = dynamic(light: 0x1A1A1A, dark: 0xFFFFEB, alpha: 0.08)

        /// Resolves per appearance, so a view is written once and both themes work.
        private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light, alpha: alpha)
            })
        }
    }

    // MARK: - Type

    /// A serif for display (New York, the system serif — close kin to the EB Garamond on
    /// Wispr's site, and nothing to bundle), the system sans for UI, mono for numbers.
    enum Font {
        /// Page titles. Pair a roman line with an italic one for the editorial look.
        static let display = SwiftUI.Font.system(size: 34, weight: .regular, design: .serif)
        static let displayItalic = display.italic()
        /// Section and card titles.
        static let title = SwiftUI.Font.system(size: 21, weight: .regular, design: .serif)
        static let titleItalic = title.italic()
        /// A transcript on the result card.
        static let quote = SwiftUI.Font.system(size: 19, weight: .regular, design: .serif)
        /// Brand wordmark in the sidebar.
        static let wordmark = SwiftUI.Font.system(size: 17, weight: .semibold, design: .serif)

        static let heading = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13)
        static let bodyEmphasis = SwiftUI.Font.system(size: 13, weight: .medium)
        static let label = SwiftUI.Font.system(size: 12)
        static let caption = SwiftUI.Font.system(size: 11)

        /// Small uppercase labels. Always with `eyebrowTracking`, always uppercased —
        /// `Eyebrow` does both.
        static let eyebrow = SwiftUI.Font.system(size: 10, weight: .bold)
        static let eyebrowTracking: CGFloat = 1.4

        /// Timings and counts. Monospaced so digits don't shift as they tick.
        static let mono = SwiftUI.Font.system(size: 11, weight: .medium, design: .monospaced).monospacedDigit()
        /// The tape counter while recording.
        static let counter = SwiftUI.Font.system(size: 26, weight: .medium, design: .monospaced).monospacedDigit()

        static let keycap = SwiftUI.Font.system(size: 11, weight: .semibold, design: .rounded)
        static let pill = SwiftUI.Font.system(size: 12, weight: .medium)
        /// The app's name on the pill — its only text.
        static let pillName = SwiftUI.Font.system(size: 12, weight: .semibold)
        /// "Release to transcribe".
        static let pillHint = SwiftUI.Font.system(size: 11.5, weight: .regular)
        static let button = SwiftUI.Font.system(size: 13, weight: .semibold)
    }

    // MARK: - Spacing

    /// A 4pt grid.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let base: CGFloat = 12
        static let roomy: CGFloat = 16
        static let wide: CGFloat = 24
        static let section: CGFloat = 32
        static let page: CGFloat = 40
    }

    // MARK: - Radius

    /// Soft and generous, like Wispr's cards — but the keycaps stay squarer, because keys are.
    enum Radius {
        static let keycap: CGFloat = 5
        static let chip: CGFloat = 7
        static let control: CGFloat = 10
        static let card: CGFloat = 18
        /// The big dictation card.
        static let deck: CGFloat = 24
    }

    // MARK: - Border

    enum Border {
        static let hairline: CGFloat = 1
        /// Selected tiles and focused fields.
        static let strong: CGFloat = 1.5
        /// How far a keycap's skirt shows below its face.
        static let keycapDepth: CGFloat = 2
    }

    // MARK: - Elevation

    /// Soft, warm, and low — paper on paper, not glass on glass.
    enum Shadow {
        static let card = Spec(opacity: 0.05, radius: 14, y: 4)
        static let raised = Spec(opacity: 0.10, radius: 22, y: 10)
        static let pill = Spec(opacity: 0.38, radius: 18, y: 8)
        /// The soft smoky halo around the glass pill.
        static let pillHalo = Spec(opacity: 0.18, radius: 26, y: 0)

        struct Spec {
            let opacity: Double
            let radius: CGFloat
            let y: CGFloat
            var color: SwiftUI.Color { .black.opacity(opacity) }
        }
    }

    // MARK: - Material

    /// The retro layer: grain, meter and waveform geometry.
    enum Material {
        /// Paper grain speck opacity. Barely there — felt more than seen.
        static let grainOpacity: Double = 0.05
        /// Specks per 10,000 pt².
        static let grainDensity: Double = 14

        /// Segmented LED meter.
        static let meterSegments = 18
        static let meterSegmentWidth: CGFloat = 5
        static let meterSegmentGap: CGFloat = 2.5
        static let meterHeight: CGFloat = 12
        /// Fraction of the meter that's green before amber, and amber before red.
        static let meterMidPoint: Double = 0.62
        static let meterHighPoint: Double = 0.85

        /// Rising bubbles above the flow pill. A trickle when quiet, a stream when loud, and
        /// one bigger lavender bubble per recognized word.
        static let bubbleRateQuiet: Double = 3        // per second, at silence
        static let bubbleRateLoud: Double = 26        // per second, at full level
        static let bubbleRadius: ClosedRange<Double> = 1.5...6
        static let wordBubbleRadius: ClosedRange<Double> = 6.5...10
        static let bubbleSpeed: ClosedRange<Double> = 38...92   // pt per second, upward
        static let bubbleLife: ClosedRange<Double> = 1.4...2.4  // seconds
        static let bubbleSpread: Double = 90           // ± pt either side of the pill's center
        static let bubbleSway: ClosedRange<Double> = 2...8      // pt of side-to-side drift
        /// Most bubbles alive at once — a ceiling so a long, loud dictation stays cheap.
        static let bubbleCap = 140



        /// Waveform bars.
        static let barWidth: CGFloat = 3
        static let barGap: CGFloat = 2.5
        static let barFloor: CGFloat = 3
    }

    // MARK: - Size

    enum Size {
        static let windowMin = CGSize(width: 900, height: 620)
        static let sidebarWidth: CGFloat = 212
        static let recentWidth: CGFloat = 290
        /// Room the traffic lights need above the sidebar's content.
        static let titlebarInset: CGFloat = 44
        static let navRowHeight: CGFloat = 34
        static let iconTile: CGFloat = 34
        static let micOrb: CGFloat = 104
        static let deckMinHeight: CGFloat = 380
        static let keycapHeight: CGFloat = 22
        static let keycapMinWidth: CGFloat = 22
        static let buttonHeight: CGFloat = 34
        static let fieldHeight: CGFloat = 32
        static let statusDot: CGFloat = 8

        // Flow pill
        /// The transparent panel the pill lives in. Larger than any pill state, so the pill
        /// can grow and shrink inside it without the window itself resizing.
        /// Room for the pill, its glow, and (if turned on) bubbles rising above it.
        static let pillCanvas = CGSize(width: 560, height: 240)
        /// Idle pill (only if turned on in Settings): a small capsule of dots.
        static let pillIdle = CGSize(width: 46, height: 12)
        /// The pill while it's working — compact: noticed, never in the way.
        static let pillHeight: CGFloat = 36
        static let pillMinWidth: CGFloat = 0
        static let pillBottomMargin: CGFloat = 22
        static let pillTextMaxWidth: CGFloat = 240
        static let pillButton: CGFloat = 22
        static let pillBars = 10
        static let pillBarsHeight: CGFloat = 18
        /// The width the voice bars take, so the transcribing dots can hold the same space.
        static let pillBarsWidth: CGFloat = CGFloat(pillBars) * (Material.barWidth + Material.barGap)
        static let pillDividerHeight: CGFloat = 16
    }

    // MARK: - Motion

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.12)
        static let standard = Animation.easeInOut(duration: 0.2)
        /// The pill growing and shrinking between states — a little give, no bounce.
        static let pill = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// The bubble popping into view — this one does bounce, once.
        static let bubblePop = Animation.spring(response: 0.38, dampingFraction: 0.58)
        /// The bubble stretching sideways into the pill.
        static let bubbleStretch = Animation.spring(response: 0.46, dampingFraction: 0.78)
        /// How long the bubble stays round before it stretches.
        static let bubbleHold: Duration = .milliseconds(110)
        /// The words fade in once the stretch is mostly done, so they're never clipped mid-way.
        static let bubbleReveal = Animation.easeOut(duration: 0.22).delay(0.18)
        /// Recording dot pulse, one full cycle.
        static let pulse: TimeInterval = 1.1
        /// Pressed buttons sink this much.
        static let pressScale: CGFloat = 0.97
    }
}

// MARK: - Hex helpers

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
