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

### Themes

`ThemeID` enum in `ThemePlayer.swift` defines 10 built-in themes: `clean`, `immersive`, `poster`, `minimal`, `vinyl`, `cassette`, `vhs`, `ipod`, `bento`, `starry`. Each exposes three capability flags:

- `supportsLyrics` — true for `clean`, `starry`, `bento`, `vinyl`, `vhs`, `minimal`
- `supportsSkipInterval` — true only for `clean`
- `supportsVolumeControl` — true only for `clean`

`SettingsViewController` uses a `PlayerSelection` enum (`.theme(ThemeID)`, `.customHTML`, `.customJS`) that mirrors these flags; it hides settings controls that don't apply to the selected theme.

`themeHTML(for:settings:)` dispatches to per-theme `*HTML(_ settings:)` functions. Lyrics-capable themes call `lyricsHelperJS(autoHide:)` which injects shared JS providing `_fetchLyrics`, `updateLyricsHighlight`, and `toggleLyrics`.

### Lyrics pipeline

1. `LyricsManager.fetch()` checks the Music app via `osascript` (supports plain and LRC-formatted embedded lyrics).
2. Falls back to LRCLIB (`https://lrclib.net/api/get`) with a 10 s timeout.
3. `version` increments on every state change (loading started, result arrived, cleared). The browser polls `/api/lyrics` only when it sees a new `lyricsVersion` in the SSE stream, with a 25 s client-side retry if the server is still fetching.

**Client-side lyrics JS behaviour (`lyricsHelperJS`):**
- `_ud` (user-dismissed): set `true` when the user manually hides the lyrics panel via the button; set `false` when user re-opens it. While `_ud=true`, auto-hide and auto-show are suppressed — the panel stays hidden across song changes until the user explicitly re-opens it.
- `_ht` (hide timer): when lyrics are still loading and the panel is open, `_status()` is NOT called immediately. Instead, a 12 s timer is started; if lyrics arrive before it fires the timer is cancelled. This prevents the panel from flashing closed on every track change.
- Per-theme `window._onLyricsToggle(open)` callback is called by `_show()` so each theme can react (e.g. Minimal adjusts `margin-top`; Bento sets explicit panel height; Starry fades the main float-root).

### Xcode project conventions

UUID pattern for manually added entries in `project.pbxproj`: `A001XXXXXXXXXXXX` (build files) / `A002XXXXXXXXXXXX` (file references). New Swift sources go in the `PBXSourcesBuildPhase`; new resources (images, SVG) go in the `PBXResourcesBuildPhase`. The package dependency on `MediaRemoteAdapter` uses `branch = master` (no version tags exist on that repo).

### Theme Archives (.theme files)

`ThemeArchiveManager` (singleton) handles import, storage, and asset serving for `.theme` archives.

A `.theme` file is a ZIP with the extension renamed. Required layout:
```
theme.json     # name, author?, version?, supportsLyrics?
styles.css     # CSS injected after default np-* layout rules
script.js      # (optional) JS injected after default onStateUpdate
assets/        # (optional) images/fonts served at /theme-assets/<filename>
```

When a theme is active (`settings.useThemeArchive == true`), `HTTPServer.servePlayer` calls `customThemeArchiveHTML(themeManager:settings:)` which generates the base HTML shell with the CSS/JS injected.

**Base HTML DOM contract** (IDs/classes available to CSS/JS):
- `#conn-dot` — connection indicator
- `.np-root` — root flex container
- `.np-artwork-wrap` / `#art` / `#art-ph` — artwork area
- `.np-info` / `#title` / `#artist` / `#album` — track info
- `.np-controls` / `.np-btn-prev` / `.np-btn-play` / `.np-btn-next` / `#ico-play` / `#ico-pause`
- `.np-seek` / `#pb-e` / `input#pb` / `#pb-r` — seek bar
- `#lyrics-panel` / `#lyric-lines` / `#btn-lyrics` (only when `supportsLyrics:true`)

**JS globals available to script.js:** `cmd()`, `elapsed()`, `fmt()`, `loadArt()`, `getState()`, `window.onStateUpdate` (override to customise state handling).

Assets in `assets/` are served at `/theme-assets/<filename>`. Path traversal (`..`) is rejected server-side.

Only one theme can be installed at a time. The archive is extracted to `~/Library/Application Support/NowPlayingRemote/ImportedTheme/`. A security warning is shown before the file picker on import.

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
| `lyricsAutoHide` | true | Auto-hide panel when no lyrics found |
| `selectedTheme` | `"clean"` | `ThemeID.rawValue` of the active built-in theme |
| `useThemeArchive` | false | When true, serve the imported `.theme` archive instead of a built-in theme |

`SettingsViewController` uses `NSSwitch` controls (macOS 10.15+) for all boolean toggles, with a label-left / switch-right row layout grouped by section (Server, Startup, Player). Theme-specific controls (skip interval, volume, lyrics) are shown/hidden and repositioned dynamically via `updateDynamicSection()`.

### SourceKit false positives

`Cannot find type 'SettingsManager' in scope` and similar errors appear across `ThemePlayer.swift` and `SettingsViewController.swift` in incremental SourceKit indexing. They are **not real errors** — the project always compiles successfully. Ignore them.
