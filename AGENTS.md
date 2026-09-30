# Working on this repo

Read this before changing anything. It's written for a coding agent picking the project up
cold: mostly things that look wrong but aren't, and things that look fine and will bite.

---

## What this is

**Saira** — push-to-talk dictation for macOS. Hold ⌥ Space, talk, let go, and cleaned
text is typed into whatever had focus. Swift 6, SwiftUI, macOS 26+. Bundle ID `ai.sai.whisper`.

Made by Sai Sesha Reddy. The push-to-talk engine started from murmur-youtube by Pat Simmons;
its Windows port, engine-comparison mode and Parakeet engine were removed and remain in git
history if ever needed.

---

## Building

**Always build with `make`.** On a Command-Line-Tools-only Mac, Swift 6.4's default build
system fails to initialise ("Unknown error parsing property list"), and against the macOS 27
SDK SwiftUI's `@State` is a macro whose plugin only ships with Xcode. The Makefile builds with
`--build-system native` against the macOS 26 SDK, and gives `make test` the swift-testing
framework path that the non-default SDK loses. With full Xcode: `make SWIFT_FLAGS= TEST_FLAGS=`.

Build products live in `~/Library/Caches/SairaBuild`, never in the repo — if the repo is
ever in an iCloud-synced folder, the sync engine mutates files mid-compile and corrupts
signatures.

---

## The rule for the dictionary

**`shared/dictionary-test-vectors.json` is the specification for correction behaviour.**
Change the vectors first, watch `make test` go red, then make it green. The copy in
`Tests/SairaDictionaryTests/` must match `shared/` — CI checks.

If you touch the regexes: NFC-normalize both pattern and text (macOS hands back decomposed
strings, and an accented trigger silently never fires otherwise), and stay in the safe subset —
`\b`, `\d`, `\w`, `\s`, classes, greedy/lazy quantifiers, alternation, named groups,
fixed-length lookbehind, lookahead, `\p{L}`, `$1`–`$9`.

---

## Design system

`Sources/Saira/UI/DesignSystem.swift` defines every color, font, size, radius, shadow and
duration. **Views must not contain literal values** — add a token instead.

Direction: the **retro edition** of a Wispr Flow–style app. The palette is Wispr Flow's own
brand set (Lumen `#FFFFEB`, Vast `#1A1A1A`, Dawn `#F0D7FF`, Fathom `#034F46`, Flare `#FF6C4C`,
Glow `#FFA946`). The retro layer: paper grain, a serif display face (New York), keycaps with a
skirt, a mono tape counter, a segmented LED meter. Rules:

- **Flare means recording.** The record dot is the only Flare in the app.
- **Lavender is for action and selection**, never for text on cream — `accentInk` is the
  readable violet.
- **Teal means live or done.**
- **The flow pill is its own look**: dark frosted glass with amber (Glow `#FFA946`) as its
  one color — ring, voice bars, dots. It's the only place a sheen gradient and glow are used,
  because Sai's reference design asked for exactly that.
- **Shadows go on background shapes, not containers.** `.shadow` on a container shadows every
  child — it haloed every keycap once. `cardStyle()` does this correctly; copy it.

Review changes with the snapshot renderer (debug builds only) rather than by eye in one theme:

```bash
make app && SAIRA_SNAPSHOT_DIR=/path/to/shots "$HOME/Library/Caches/SairaBuild/Saira.app/Contents/MacOS/Saira"
```

It draws in-process with `cacheDisplay`, so it needs no Screen Recording permission, and it
never arms the shortcut or prompts for permissions.

---

## Things that look like bugs and are not

**A dictation started from the app window doesn't type anything.** By design — there's no
foreign text field to type into. It waits on the result card; **Insert** hides the app and types
into whichever app comes forward.

**⌥ Space is swallowed, ⌥ is not.** The tap consumes Space's down, repeats and up, but always
passes the modifier's `flagsChanged` through — if the target app never saw ⌥ come up, it would
think ⌥ was held forever. Space keeps being swallowed until its key-up even if ⌥ was released
first, or a held Space would start typing spaces.

**Esc is only swallowed while dictating.** `DictationController.cancel()` returns whether it
cancelled anything; the tap passes Esc through otherwise. Don't add Esc as a menu key
equivalent — it would steal Esc from sheets and fields.

**A quick tap of the shortcut does nothing.** A hold must last `holdThreshold` (300 ms) to
engage; before that there's no pill, no sound, and releasing — or pressing another key, like
fn+arrow — cancels silently. Audio is captured from the first instant, so nothing is lost.

**The app ignores saved window state** (`ApplePersistenceIgnoreState`, set in `App.init`). If
the main window was closed at quit, macOS would otherwise relaunch with no window at all —
which overrides `.defaultLaunchBehavior(.presented)` — and the app looks like it didn't open.

**⌘Q doesn't quit.** It closes the window and keeps Saira listening from the menu bar (no
Dock icon, `.accessory`). The real quit is ⌥⌘Q or the menu-bar item. A dictation app that stops
listening because of a habitual ⌘Q is broken from the user's side.

**Saira opts out of Automatic Termination, Sudden Termination and App Nap** (Info.plist and
`AppDelegate.stayAlive()`). With no window open, macOS otherwise ends or throttles it and the
shortcut dies silently until relaunch — this was a real, reported bug. A watchdog
(`keepShortcutAlive`, every 2 s and on wake/unlock) re-enables a tap macOS switched off,
re-creates a missing one, and sends a key-up that was missed while it was off.

**The pill's window is bigger than the pill.** `HUDPanel` is a fixed transparent canvas; the
pill animates inside it. Clicks on transparent pixels fall through to the app below.

---

## Things that will bite

**`MainActor.assumeIsolated` crashes the process when wrong.** It asserts, it doesn't check.
It's used only where the thread is guaranteed (the event-tap callback on the main run loop, a
`.main`-queue notification). Anywhere else use `await MainActor.run`.

**Closures handed to audio APIs from `@MainActor` code must be explicitly `@Sendable`.** In
Swift 6 mode, a closure formed in a main-actor context inherits that isolation and traps when
the audio thread calls it. See `MicTest.start`.

**Code signing is load-bearing.** TCC stores a code-signing *requirement*. Ad-hoc signatures
change every build, so the Accessibility toggle stays **on** while the app is untrusted. The
Makefile prefers a Developer ID, then a self-signed "Saira Local Signing" identity,
then ad-hoc; don't replace that with `--sign -`. To reset a wedged
grant: `tccutil reset Accessibility ai.sai.whisper` — never omit the bundle ID, which wipes every
app on the machine — then ⌘Q System Settings before reopening.

**Smart cleanup is the slow part.** On this Mac a cold on-device model took ~4 s even for two
words and usually timed out, so every dictation waited 4 s for the rule-based result. It's now
prewarmed at key-down and capped at 2.5 s, and it's off by default for speed. Every dictation
logs `timing · transcribe … · cleanup … · total …` (category `speech`, needs `--info`) — read
that before guessing at latency.

**`log` may be shadowed in the user's shell.** Use `/usr/bin/log`, subsystem `ai.sai.whisper`.

---

## What isn't built

1. **Command Mode** — select text, hold a second key, "make this more formal."
2. **Onboarding** — a first-run permissions walkthrough.
3. **A custom shortcut recorder** — `Shortcut` is a fixed enum of four.
4. **Notarization / Developer ID signing.**
