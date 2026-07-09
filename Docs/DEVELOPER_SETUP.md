# Developer Setup Guide

This guide covers how to set up your development environment to build, modify, and extend Now Playing Remote.

## Prerequisites

- **macOS 11+** (Big Sur or later)
- **Xcode 13+** with Command Line Tools
- **Swift 5.5+**
- A local text editor or IDE (Xcode, VS Code with Swift extension, etc.)

## Initial Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd Now-Playing-Remote
```

### 2. Open in Xcode

```bash
open NowPlayingRemote.xcodeproj
```

### 3. Build the Project

**Debug build:**
```bash
xcodebuild -project NowPlayingRemote.xcodeproj -scheme NowPlayingRemote -configuration Debug build
```

**Release build:**
```bash
xcodebuild -project NowPlayingRemote.xcodeproj -scheme NowPlayingRemote -configuration Release build
```

Or simply press **⌘B** in Xcode.

### 4. Run the App

Press **⌘R** in Xcode or:
```bash
open build/Debug/NowPlayingRemote.app
```

## Project Structure

```
NowPlayingRemote/
├── main.swift                    # App entry point, delegate setup
├── AppDelegate.swift             # Lifecycle, component wiring
├── MediaController.swift         # MediaRemote wrapper, playback state
├── LyricsManager.swift           # Lyrics fetching (Music app + LRCLIB)
├── HTTPServer.swift              # POSIX socket server, routes, SSE
├── MenuBarController.swift       # NSStatusItem, menu, settings window
├── SettingsManager.swift         # UserDefaults wrapper
├── SettingsViewController.swift  # Settings UI
├── QRCodeWindowController.swift  # QR code panel
├── ThemePlayer.swift             # Theme HTML/JS generation
├── ThemeArchiveManager.swift     # .theme archive install/serve
└── MediaRemoteAdapter.swift      # (Package dependency)

Assets/
├── HomescreenIcon.png            # 180×180 touch icon
└── AppIcon.appiconset/           # Xcode asset catalog
```

## Key Files for Development

### HTTPServer.swift
The heart of the app. Contains:
- POSIX TCP socket setup (`AF_INET / SOCK_STREAM`)
- Route dispatch (GET `/`, `/api/*`, POST `/api/command`)
- SSE stream management
- Asset serving

**Key functions:**
- `handleRequest(_ fd:)` — Parse HTTP request and dispatch
- `servePlayer(_ fd:)` — Serve the web player HTML
- `broadcastStateUpdate()` — Push state to all connected clients
- `serveThemeAsset(_ fd: path:)` — Serve theme archive assets

### ThemePlayer.swift
Theme HTML generation and lyrics JavaScript.

**Key functions:**
- `themeHTML(for:settings:)` — Dispatch to theme-specific HTML functions
- `cleanHTML(_ settings:)`, `immersiveHTML(_ settings:)`, etc. — Per-theme HTML
- `lyricsHelperJS(autoHide:)` — Injected JS for lyrics panel management
- `customThemeArchiveHTML(themeManager:settings:)` — Base HTML shell for `.theme` archives

### SettingsViewController.swift
Programmatic NSKit UI for the settings panel.

**Key classes/methods:**
- `buildModernUI()` — Construct the UI with `NSStackView` and `NSSwitch`
- `createCard(_ title: NSAttributedString)` — Card wrapper
- `createRow(title:labelOverride:controls:)` — Settings row
- `updateDynamicSection()` — Show/hide theme-specific controls

### MediaController.swift
Wraps `MediaRemoteAdapter` to provide playback control and state snapshots.

**Key properties:**
- `stateJSON()` — Serializable playback state
- `artworkPNGData()` — Current artwork as PNG
- `artworkVersion` — Cache-bust token for artwork changes

### ThemeArchiveManager.swift
Singleton for theme archive installation and asset serving.

**Key methods:**
- `installTheme(from sourceURL:)` — Extract ZIP and verify manifest
- `manifest()` — Read `theme.json` metadata
- `css()`, `js()` — Load styles and scripts
- `assetData(name:)` — Serve assets with path traversal protection

## Building and Testing

### No Automated Tests
There are no unit tests or integration tests. Verification is manual:

1. Build the project
2. Run the app from Xcode (⌘R)
3. Open `http://localhost:8080` in a browser (or another device on your network)
4. Test playback controls, lyrics, theme switching, etc.

### Common Build Issues

**"Cannot find type 'SettingsManager' in scope"**
- These are false positives from SourceKit's incremental indexing
- The project always compiles successfully
- Ignore these warnings — they are not real errors

**"borderType was deprecated"**
- Pre-existing warning in `SettingsViewController.swift`
- Not critical; related to `NSBox` border styling

### Debugging

**Print debugging:**
```swift
print("State update: \(state)")
```

**Run with Console:**
```bash
open /Applications/Utilities/Console.app
# Filter by process "NowPlayingRemote" to see prints
```

**Xcode debugger:**
- Set breakpoints in Xcode (click line number)
- Run with ⌘R and step through code (F6, F7, F8)

## Code Style

The codebase uses:
- **Swift style** — no external formatting tools
- **Comments** — minimal; only when the WHY is non-obvious
- **Naming** — descriptive function/variable names
- **No force unwrap** — avoid `!` unless you're certain
- **Prefer `guard` over nested `if`** — flattens code

## Working with Dependencies

### MediaRemoteAdapter Package
The project depends on `MediaRemoteAdapter` (via SPM). To update:

1. Xcode > File > Add Packages
2. Enter the repository URL
3. Select branch/version
4. Check the "NowPlayingRemote" target

The current setup uses `branch = master` (no stable version tags).

## HTTP Server Details

### Thread Safety
The server uses three dispatch queues to avoid race conditions:

- **acceptQueue** (serial) — runs the `accept()` loop
- **handleQueue** (concurrent) — processes individual requests
- **sseQueue** (serial) — owns the SSE client list

All state mutations on `[SSEClient]` go through `sseQueue` to prevent races.

### SSE (Server-Sent Events)

SSE keeps one persistent TCP connection open per browser. The server:
1. Sends the current state immediately on connect
2. Broadcasts state updates when playback changes
3. Sends a ping (`: ping` comment) every 25 seconds to detect dead connections

**Client-side (browser):**
```js
const es = new EventSource('/events');
es.onmessage = e => applyState(JSON.parse(e.data));
```

### Route Examples

**Serve the player:**
```swift
case ("GET", "/"):
  servePlayer(fd)
```

**Serve state JSON:**
```swift
case ("GET", "/api/state"):
  let json = mediaController.stateJSON()
  respond(fd, 200, "application/json", json)
```

**Dispatch a command:**
```swift
case ("POST", "/api/command"):
  let cmd = parseJSON(body)["command"]
  mediaController.handleCommand(cmd)
```

## Building a Theme

See [THEME_DEVELOPMENT.md](THEME_DEVELOPMENT.md) for step-by-step instructions.

## Modifying the Settings UI

The settings UI is built programmatically with `NSStackView`. To add a new setting:

1. Add a key to `SettingsManager.swift`:
```swift
var newSetting: Bool {
  get { defaults.object(forKey: "newSetting") as? Bool ?? false }
  set { defaults.set(newValue, forKey: "newSetting") }
}
```

2. Add a control in `SettingsViewController.buildModernUI()`:
```swift
let toggle = NSSwitch()
toggle.target = self
toggle.action = #selector(newSettingChanged)
// ... add to mainStack
```

3. Handle the change:
```swift
@objc private func newSettingChanged(_ sender: NSSwitch) {
  settings.newSetting = sender.state == .on
}
```

## Architecture Decisions

- **POSIX sockets, not frameworks** — HTTPServer uses raw socket APIs for simplicity and control
- **No database** — UserDefaults for all persistence
- **No external HTTP framework** — built on standard library and POSIX APIs
- **SSE over WebSocket** — simpler protocol, no frame overhead
- **Menu-bar app (LSUIElement)** — no Dock icon, minimal footprint

## Performance Considerations

- **Artwork versioning** — prevents redundant image fetches
- **SSE ping timer** — detects dead connections without polling
- **Concurrent request queue** — handles multiple simultaneous browsers
- **Lazy theme HTML generation** — only generated on demand

## Useful Commands

```bash
# Build from command line
xcodebuild -project NowPlayingRemote.xcodeproj -scheme NowPlayingRemote build

# View system logs
log stream --predicate 'process == "NowPlayingRemote"'

# Find your Mac's IP
ifconfig | grep "inet " | grep -v 127.0.0.1

# Kill the app
pkill NowPlayingRemote
```

## Git Workflow

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/description
   ```

2. **Commit your changes:**
   ```bash
   git add .
   git commit -m "Brief description"
   ```

3. **Push and create a pull request:**
   ```bash
   git push origin feature/description
   ```

## Next Steps

- Explore `HTTPServer.swift` to understand the request/response cycle
- Modify `cleanHTML()` in `ThemePlayer.swift` to customize the default theme
- Add a new route to `HTTPServer` for a custom API endpoint
- Read [THEME_DEVELOPMENT.md](THEME_DEVELOPMENT.md) to create a `.theme` archive

