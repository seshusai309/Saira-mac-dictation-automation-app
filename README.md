# Saira

**Your voice. Higher productivity.**
Made by **Sai Sesha Reddy**.

Hold a key, talk, let go — and clean, punctuated text appears wherever you're typing: email,
Slack, Notes, a browser, a code editor. Everything happens on your Mac. Nothing you say is
sent anywhere.

---

## Install it on your Mac

About 5 minutes. No coding, no AI, nothing to buy.

**You need:** a Mac with **macOS 26 (Tahoe) or newer**. To check: Apple menu  ▸ About This Mac.

### 1. Open Terminal

Press **⌘ Command + Space**, type **Terminal**, press **Return**.

### 2. Install Apple's free developer tools *(skip if you've done this before)*

Copy this line, paste it into Terminal, press **Return**:

```
xcode-select --install
```

A window pops up — click **Install** and wait until it says it's done (5–15 minutes).
If Terminal says *"already installed"*, that's fine — go on.

### 3. Download and install Saira

Copy this line, paste it into Terminal, press **Return**:

```
git clone https://github.com/seshusai309/Saira-mac-dictation-automation-app.git ~/saira && ~/saira/install.sh
```

Wait about a minute. When it says **Done**, Saira is in your Applications folder and
open.

> **No `git`?** On the GitHub page, click the green **Code** button ▸ **Download ZIP**. Open the
> ZIP (it unpacks into your Downloads folder), then paste this into Terminal instead:
> `~/Downloads/Saira-mac-dictation-automation-app-main/install.sh`

### 4. Allow it to work in every app *(one time)*

Open **System Settings ▸ Privacy & Security ▸ Accessibility** and turn on **Saira**.
It switches on by itself — no restart needed.

### 5. Talk

Click into any text box. **Hold ⌥ Option + Space**, say something, let go. The first time,
click **Allow** when it asks for the microphone.

That's it. It also starts by itself whenever your Mac starts (you can turn that off in
Settings ▸ Startup).

### Good to know

- **Prefer the fn key?** In Saira ▸ Settings, pick **fn**. Then open System Settings ▸
  Keyboard and set **"Press 🌐 key to"** to **Do Nothing** — otherwise macOS answers fn too.
  A quick tap of fn does nothing; *hold* it to dictate.
- **Esc** cancels a dictation.
- **Closing the window keeps Saira listening.** Click the red ✕ and it keeps running — its Dock
  icon stays, and your shortcut keeps working. **⌘Q quits it completely**; the shortcut then
  does nothing until you open Saira again (it also starts by itself when your Mac starts).
- **Update to a newer version:** paste `cd ~/saira && git pull && ./install.sh`, then
  turn Accessibility back on (step 4) — macOS asks again after every reinstall.
- **Shortcut stopped working?** Open Saira and read the banner at the top:
  - *"Your shortcut is off"* — click **Fix** and turn it on again in the window that opens.
  - *"Your shortcut is paused by …"* — that app has macOS **Secure Input** on (usually a
    password field), which hides key presses from every app on the Mac. Saira comes back by
    itself when it's released. If it stays stuck: lock the screen (⌃⌘Q) and unlock, or quit
    that app. In Terminal, untick *Terminal ▸ Secure Keyboard Entry*.
- **Uninstall:** quit it with ⌘Q, then drag *Saira* from Applications to the
  Trash. Your history and dictionary are in `~/Library/Application Support/Saira` if you
  want those gone too.

---

## What's in it

**The pill** — a small frosted-glass pill at the bottom of the screen: amber bars that move with
your voice, and "Saira". It pops up like a bubble only when you *hold* the shortcut, and
disappears the moment your text is typed. Optional voice bubbles rise off it as you talk
(Settings ▸ Voice bubbles).

**Dictate** — start a dictation from the app itself, then **Copy**, **Edit** or **Insert** the
result. Your recent dictations sit beside it.

**History** — everything you've said, searchable, with any dictionary corrections shown.

**Templates** — Everyday, Notes, Code, Content, Tasks: each shapes the cleanup for where your
words are going. *Code* keeps commands exact; *Tasks* turns a spoken list into a checklist.

**Dictionary** — teach it names and jargon it gets wrong: words it should know, and
corrections like `cloud code → Claude Code`. Also a plain text file you can edit.

**Settings** — start with your Mac, shortcut (⌥ Space, Right ⌥, fn, Right ⌘) and hold vs.
press-once, language, microphone with a level test, Smart cleanup, typing vs. copy-only,
sounds, light/dark theme, permission status.

**Private by design.** Speech recognition is Apple's own engine, built into macOS — nothing to
download, and the app uses about 50 MB of memory. *Smart cleanup* (optional) uses Apple's
on-device AI model. Nothing ever leaves your Mac.

---

## For developers

```bash
make install     # build, bundle, sign, copy to /Applications, launch
make test        # the dictionary's behaviour tests
make app         # bundle only        make run    # run in place
make icon        # regenerate the app icon      make clean
```

Swift 6, SwiftUI, macOS 26+, no third-party dependencies. See `AGENTS.md` for the rules the
code follows and the traps worth knowing about.

> **Toolchain note.** On a Mac with only the Command Line Tools, Swift 6.4's default build
> system can't start, and the macOS 27 SDK needs an Xcode-only SwiftUI macro plugin. The
> Makefile works around both by building with the native build system against the macOS 26
> SDK. With full Xcode installed, `make SWIFT_FLAGS= TEST_FLAGS=` uses the defaults.

### Architecture

```
 shortcut ─► HotkeyMonitor ──► DictationController ◄── Settings
                                │
                     ┌──────────┼──────────┐
                     ▼          ▼          ▼
              AudioCapture   FlowPill   TranscriptionEngine
                     │                      │
                (AudioChunk) ──ordered──► Apple SpeechAnalyzer
                                            │
                                       TextFormatter (+ template)
                                            ▼
                                    DictionaryCorrector
                                            ▼
                                       TextInjector ─► focused app
```

```
Sources/Saira/
├── SairaApp.swift          @main, AppDelegate, menu bar
├── Core/                         controller, shortcut tap, capture, mic devices, injector
├── Transcription/                engine protocol, Apple SpeechAnalyzer
├── Formatting/                   rule-based + on-device LLM cleanup, templates
├── Dictionary/                   the plain-text dictionary store
├── UI/                           design tokens, components, screens, the pill
└── Support/                      settings, history, paths, login item, permissions, snapshots
Sources/SairaDictionary/        the correction engine, tested against shared/ vectors
install.sh                        the one-command installer from "Install it on your Mac"
```

**The pill never takes focus.** `HUDPanel` is a `.nonactivatingPanel` with
`canBecomeKey == false` — otherwise your text field would lose focus and there'd be nothing to
type into.

**The shortcut needs a `CGEventTap`** — the only API that sees left/right modifiers and `fn`,
and that can *swallow* ⌥ Space so it doesn't also type a space. That's why Accessibility
permission is required.

**Audio ordering is explicit.** Capture yields into an `AsyncStream` drained by one task; a
`Task` per buffer would scramble the audio.

**Design review without screenshots:** debug builds render every screen, both themes and every
pill state to PNGs:
`SAIRA_SNAPSHOT_DIR=~/Desktop/shots "$HOME/Library/Caches/SairaBuild/Saira.app/Contents/MacOS/Saira"`

**Why Accessibility is asked again after each rebuild:** without an Apple Developer ID the app
is ad-hoc signed, and macOS ties the permission to the signature. To stop that on your own Mac,
create a self-signed certificate once — Keychain Access ▸ Certificate Assistant ▸ Create a
Certificate…, name **Saira Local Signing**, type **Code Signing** — and the Makefile
uses it automatically. A stuck permission resets with
`tccutil reset Accessibility ai.sai.whisper` (always pass the bundle ID).

### Not built yet

1. **Command Mode** — select text, hold a second key, "make this more formal."
2. **Onboarding** — a first-run window for the permissions (Settings shows their status).
3. **A custom shortcut recorder** — the four shortcuts are a fixed list today.

---

## Credits

Saira is designed and developed by **Sai Sesha Reddy**. Its push-to-talk engine
