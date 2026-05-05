<div align="center">

<img src="app-icon.png" alt="Dramatic Events" width="160" />

# Dramatic Events

**A macOS menu-bar countdown to your next calendar meeting — with a dramatic 10-second sound entrance.**

[![Download](https://img.shields.io/badge/Download-Dramatic_Events.dmg-FF3B48?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/ulvosama/dramatic-events/releases/latest/download/Dramatic-Events.dmg)
[![Latest release](https://img.shields.io/github/v/release/ulvosama/dramatic-events?style=for-the-badge&label=Latest)](https://github.com/ulvosama/dramatic-events/releases/latest)
[![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-black?style=for-the-badge&logo=apple)](https://github.com/ulvosama/dramatic-events/releases/latest)

</div>

---

## What it does

A small monitor icon sits in your menu bar with the title of your **next calendar event** and a live countdown:

```
🖥  Product huddle in 1:23
```

When 10 seconds remain, the item turns **bright red**, the icon switches to a pulsing on-air light, and your sound starts playing with a 2-second fade-in. The moment the meeting starts, it flips to **"Product huddle is live!"** and the music cuts. After 60 seconds the next event takes over.

Inspired by [Riley Walz's viral video](https://x.com/rrwalz) where a meeting countdown plays the BBC News theme as it hits zero.

## Features

- **Live countdown** in the menu bar — `H:MM` format until the last minute, then `SSs` so digits don't jitter (monospaced).
- **Dramatic 10-second entrance** — red background, slow-pulsing white circle, your chosen sound fading in.
- **"Live!" state** for the first minute of the meeting.
- **Join button** auto-detects Zoom / Google Meet / Teams / Webex links in the event and lets you jump straight in from the dropdown.
- **Custom sound** — pick any audio file (MP3, WAV, M4A, AIFF). Trim it to the 10-second slice you want.
- **Open at login** so it survives every restart.
- **Auto-update check** — see when a new release ships.

## Install

1. **[Download Dramatic-Events.dmg](https://github.com/ulvosama/dramatic-events/releases/latest/download/Dramatic-Events.dmg)**
2. Open the DMG and drag **Dramatic Events** to your Applications folder.
3. Launch it. Approve the **Calendar access** prompt on first launch.
4. (Optional) Click the menu-bar icon → **Settings…** → toggle **Open at login**.

The app runs hidden — no Dock icon, no window. Look in the top-right of your screen for the menu-bar item.

## First-run permissions

macOS will ask once for **Calendar** access. If you accidentally deny it, re-enable from:

> System Settings → Privacy & Security → Calendars → Dramatic Events

## Settings

| | |
|---|---|
| **Choose Music…** | Pick any audio file. It's copied into `~/Library/Application Support/Dramatic Events/`. |
| **Trim slider** | Choose which 10-second slice of the file plays. |
| **Preview 10s** | Hear the slice exactly as it'll fire. |
| **Open at login** | Auto-launch on every login (uses macOS `SMAppService`). |
| **Check for updates** | Hits this repo's releases. Shows a Download button when a new version is available. |

`⌘W` closes the Settings window. `⌘Q` prompts before quitting.

## Building from source

You don't need Xcode — the project builds with the system Swift toolchain.

```bash
git clone https://github.com/ulvosama/dramatic-events.git
cd dramatic-events
./build.sh                    # → build/Dramatic Events.app
./package-dmg.sh              # → build/Dramatic-Events.dmg
```

Requirements:
- macOS 14 (Sonoma) or newer
- Command Line Tools for Xcode (`xcode-select --install`)
- Apple Silicon (the build script targets `arm64-apple-macos14.0`)

## Releasing a new version (for maintainers)

The full workflow is in [`RELEASING.md`](RELEASING.md). TL;DR:

```bash
# 1. Bump CFBundleShortVersionString and CFBundleVersion in DramaticEvents/Info.plist
# 2. Build the DMG
./package-dmg.sh

# 3. Tag and push
git commit -am "Release 1.0.1"
git tag v1.0.1
git push --follow-tags

# 4. Create the GitHub release with the DMG attached
gh release create v1.0.1 'build/Dramatic-Events.dmg' \
    --title "Dramatic Events v1.0.1" \
    --notes "What's new in this release..."
```

Every running copy of the app polls the GitHub API on Settings open and shows an "Update available" banner when a newer tag exists.

## Tech

- **Swift 5.10** + AppKit (no SwiftUI — the menu-bar item needs `NSStatusItem` for dynamic colored backgrounds).
- **EventKit** for calendar access.
- **AVAudioPlayer** for sound playback with `setVolume(_:fadeDuration:)` for the 2-second fade-in.
- **`ProcessInfo.beginActivity`** to suppress App Nap so the 1-second timer keeps firing while you're in another app.
- **`SMAppService.mainApp`** for the "Open at login" toggle.
- **Ad-hoc code-signing** so it runs anywhere without a paid Apple Developer account.

## License

MIT.

---

<div align="center">

Made by <a href="https://www.linkedin.com/in/ulvosama/">Omar Osama</a>

</div>
