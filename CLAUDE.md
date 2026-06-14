# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
# Build (Debug)
xcodebuild -project NowPlayingRemote.xcodeproj -scheme NowPlayingRemote -configuration Debug build

# Build (Release)
xcodebuild -project NowPlayingRemote.xcodeproj -scheme NowPlayingRemote -configuration Release build
```

There are no automated tests. Verify changes by running the app from Xcode and connecting a browser to `http://<mac-ip>:8080`.

## Architecture

The app is a macOS menu-bar utility (`LSUIElement = true`, no Dock icon). Entry point is `main.swift` — `@main` is intentionally **not** used because it does not wire the delegate without a NIB; the delegate is set explicitly before `app.run()`.

### Component map

| File | Responsibility |
|---|---|
| `AppDelegate.swift` | Wires everything together; owns the lifecycle callbacks between `MediaController`, `LyricsManager`, and `HTTPServer` |
| `MediaController.swift` | Wraps `MediaRemoteAdapter`; exposes playback controls, `stateJSON()`, `artworkPNGData()`, `artworkVersion` |
| `LyricsManager.swift` | Fetches lyrics (Music app AppleScript → LRCLIB fallback); owns a `version` int used as a cache-bust token |
| `HTTPServer.swift` | POSIX TCP socket server (no framework); serves the web player and all API endpoints |
| `MenuBarController.swift` | NSStatusItem, menu, settings window, QR code panel |
| `SettingsManager.swift` | Thin `UserDefaults` wrapper; all persisted keys live here |
| `SettingsViewController.swift` | Programmatic `NSViewController` for the settings panel |
| `QRCodeWindowController.swift` | Generates a QR code via `CIQRCodeGenerator` and shows it in a floating `NSPanel` |

### HTTP server internals

`HTTPServer` uses raw POSIX sockets (`AF_INET / SOCK_STREAM`) with two `DispatchQueue`s:
- `acceptQueue` — serial, runs the `accept()` loop
- `handleQueue` — concurrent, handles individual requests
- `sseQueue` — serial, owns the `[SSEClient]` array to avoid races

**Routes**

| Method | Path | Handler |
|---|---|---|
| GET | `/` | Serves the embedded HTML player |
| GET | `/api/state` | Returns `MediaController.stateJSON()` as JSON |
| GET | `/api/artwork` | Returns the current artwork as PNG (`Cache-Control: no-store`) |
| GET | `/api/lyrics` | Returns `LyricsManager.currentLyricsJSON()` |
| GET | `/events` | Opens an SSE stream; client stays connected |
| POST | `/api/command` | Dispatches playback commands to `MediaController` |
| GET | `/manifest.json` | PWA web app manifest |
| GET | `/icon-180.png` | 180×180 homescreen icon (lazy-rendered from `HomescreenIcon.png`) |

**Real-time updates** use Server-Sent Events. `broadcastStateUpdate()` serialises `stateJSON()` + `lyricsVersion` and writes to all open SSE connections. A ping timer fires every 25 s to detect dead connections via `poll(POLLHUP|POLLERR)`.

### State change flow

```
MediaRemoteAdapter callback
  → MediaController.onUpdate
    → LyricsManager.fetch()          (if lyrics enabled and track changed)
    → HTTPServer.broadcastStateUpdate()   (SSE push to all browsers)
    → MenuBarController.updateMenu()

LyricsManager.onLyricsReady
  → HTTPServer.broadcastStateUpdate()   (sends incremented lyricsVersion)
```

### Artwork version tracking

`MediaController` tracks `artworkVersion: Int` using `ObjectIdentifier` on the `NSImage` returned by `MediaRemoteAdapter`. The version increments only when the artwork *object* changes, preventing the browser from fetching stale artwork when MediaRemote fires the track-info callback before the artwork is ready.

### Lyrics pipeline

1. `LyricsManager.fetch()` checks the Music app via `osascript` (supports plain and LRC-formatted embedded lyrics).
2. Falls back to LRCLIB (`https://lrclib.net/api/get`) with a 10 s timeout.
3. `version` increments on every state change (loading started, result arrived, cleared). The browser polls `/api/lyrics` only when it sees a new `lyricsVersion` in the SSE stream, with a 25 s client-side retry if the server is still fetching.

### Xcode project conventions

UUID pattern for manually added entries in `project.pbxproj`: `A001XXXXXXXXXXXX` (build files) / `A002XXXXXXXXXXXX` (file references). New Swift sources go in the `PBXSourcesBuildPhase`; new resources (images, SVG) go in the `PBXResourcesBuildPhase`. The package dependency on `MediaRemoteAdapter` uses `branch = master` (no version tags exist on that repo).

### Settings keys (`UserDefaults`)

| Key | Default | Controls |
|---|---|---|
| `serverPort` | 8080 | HTTP listen port |
| `autoStartServer` | true | Start server on launch |
| `skipInterval` | 15 | Skip forward/back seconds |
| `showVolumeControl` | false | Volume slider in web player |
| `showLikeButton` | false | Like button (unused in current UI) |
| `launchAtLogin` | false | `SMAppService.mainApp` |
| `showLyrics` | true | Lyrics panel + LRCLIB fetching |
