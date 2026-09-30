#!/bin/bash
#
# SAI's Whisper — one-command installer.
#
# Builds the app from this folder, puts it in /Applications and opens it.
# Run it from Terminal:   ./install.sh
# Run it again any time to update after downloading a newer copy.

set -e
cd "$(dirname "$0")"

bold() { printf "\n\033[1m%s\033[0m\n" "$1"; }

# 1. The speech engine SAI's Whisper uses ships with macOS 26 (Tahoe) and newer.
version=$(sw_vers -productVersion)
major=${version%%.*}
if [ "$major" -lt 26 ]; then
    bold "SAI's Whisper needs macOS 26 (Tahoe) or newer — this Mac has macOS $version."
    echo "Update in System Settings ▸ General ▸ Software Update, then run ./install.sh again."
    exit 1
fi

# 2. Apple's free Command Line Tools provide the Swift compiler used to build the app.
if ! xcode-select -p >/dev/null 2>&1; then
    bold "First, Apple's Command Line Tools are needed (free, from Apple)."
    echo "A window will pop up — click Install and wait for it to finish (5–15 minutes)."
    xcode-select --install >/dev/null 2>&1 || true
    echo
    echo "When it's done, run ./install.sh again."
    exit 0
fi

bold "Building SAI's Whisper… (about a minute the first time)"
make install

bold "Done — SAI's Whisper is in your Applications folder and running."
cat <<'EOF'

One last step, one time only:

  System Settings ▸ Privacy & Security ▸ Accessibility ▸ turn on "SAI's Whisper".
  (This lets it hear your shortcut in every app and type the text for you.)

Then click into any text box, hold ⌥ Option + Space, talk, and let go.
It will ask for the microphone the first time — click Allow.

Prefer the fn key? Choose it in SAI's Whisper ▸ Settings, then set
System Settings ▸ Keyboard ▸ "Press 🌐 key to" ▸ Do Nothing.

EOF
