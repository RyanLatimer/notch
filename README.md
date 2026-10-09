# Notch

A free Alcove/NotchNook-style app that turns the MacBook notch into a live, interactive
"Dynamic Island". Written in Swift + SwiftUI and built entirely in GitHub Actions, so you
don't need Xcode or a Mac to produce it. You only need the Mac to run it.

## Features

- **Hover to open**: the notch smoothly expands into a panel (or opens on click if you prefer), with optional trackpad haptics.
- **Now playing**: artwork, title and artist, a scrubbable progress bar, and play/pause/next/previous.
  It works with Spotify, Apple Music, browsers (YouTube, etc.), Podcasts, and anything else that reports to macOS.
- **Live activities** in the collapsed notch:
  - album art plus an animated visualizer tinted with the artwork's color while music plays
  - a charging indicator when you plug in
  - volume and brightness levels
- **System HUD replacement** (optional): take over the volume and brightness keys and hide the macOS overlay. Hold ⌥⇧ for fine steps.
- **Calendar**: today's date, a week strip, and your next events.
- **File shelf**: drag files onto the notch to park them, then drag them out later, AirDrop them, or open them.
- Battery level in the header, launch at login, a menu bar icon you can hide, and an optional virtual notch on displays that don't have one.

## Install (on your MacBook)

1. Download `Notch.zip` from the [latest release](https://github.com/RyanLatimer/notch/releases/tag/latest).
2. Double-click the zip and put `Notch.app` wherever you like. **You don't need the main Applications folder or an admin password.**
   A good spot is an `Applications` folder inside your home folder (`~/Applications`); create it in Finder if it doesn't exist.
   Your Desktop or Documents folder also works.
3. The app isn't notarized (that needs a paid Apple developer account), so clear the download quarantine once.
   Open **Terminal** and run this, replacing the path if you put the app somewhere else:
   ```sh
   xattr -cr ~/Applications/Notch.app
   ```
   Clearing the quarantine also keeps macOS from silently running the app from a temporary read-only copy,
   which would break launch at login.
4. Open Notch. The settings window appears on first launch. After that, use the menu bar icon or the ⚙︎ in the expanded notch.
   Don't move the app after turning on **Launch at login**. If you do move it, toggle the setting off and on again.

### Permissions (macOS asks the first time each one is needed)

| Permission | Why |
|---|---|
| Automation → Spotify / Music | Only used if the fallback AppleScript media source is active |
| Calendars | Only after you click **Show events** in the notch |
| Accessibility | Only if you turn on **Replace the system volume & brightness HUD** |

> **Updating:** because builds are ad-hoc signed, macOS treats each new build as a different app.
> After updating, replace the old `Notch.app` in the same place and re-run the `xattr` command. If you use HUD replacement, also remove and re-add
> Notch under System Settings → Privacy & Security → Accessibility.

## Building

Every push to `main` triggers `.github/workflows/build.yml`. The workflow runs on a macOS runner and:

1. compiles a universal (Apple Silicon + Intel) binary with SwiftPM, with no Xcode project involved
2. builds the bundled [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
3. assembles, ad-hoc signs, and zips `Notch.app`
4. launches it in demo mode as a smoke test and uploads a screenshot artifact
5. publishes the zip to the rolling **latest** release

Pushing a tag like `v1.0.0` creates a versioned release instead.

If you ever have a Mac with the Command Line Tools installed (`xcode-select --install`, no full Xcode needed),
you can build locally with `./scripts/build-app.sh`.

## How it works

- The notch is a borderless, non-activating `NSPanel` that sits above the menu bar on every Space.
  The panel ignores the mouse except when the pointer is over the notch, so it never blocks the menu bar.
- The notch size comes from `NSScreen.safeAreaInsets` and the auxiliary top areas, so it matches the real camera housing.
- **Now playing:** since macOS 15.4, only Apple-signed processes can read the system's now-playing state.
  Notch runs the bundled adapter script with the system `/usr/bin/perl`, which still has access, and streams JSON updates from it.
  If the adapter stops working on a future macOS, Notch automatically switches to AppleScript for Spotify and Music.
  You can also pick the source under Settings → Media.
- **Volume** changes come from CoreAudio property listeners. **Brightness** uses the private DisplayServices framework, loaded dynamically.
  HUD replacement uses a `CGEventTap` on the media-key events.

## Project layout

```
Sources/Notch/
  App/        entry point, app delegate, settings model
  Notch/      panel, notch shape, geometry & hover state machine
  Views/      SwiftUI: collapsed activities, expanded panel, player, calendar, shelf, settings
  Services/   media (MediaRemote + AppleScript), battery, volume/brightness HUD, calendar, shelf
scripts/      build-app.sh, make-icon.swift
```

## Credits

The MediaRemote adapter is © Jonas van den Berg ([ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)), BSD-3-Clause.
Its license ships inside the app bundle.
