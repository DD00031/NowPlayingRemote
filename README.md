# Now Playing Remote

A macOS menu-bar app that lets you control and view the currently playing media from your phone or any device on the same network. It hosts a local HTTP server that serves a mobile-optimised web player, accessible via a URL or QR code.

## Features

- **Real-time updates** via Server-Sent Events — no polling
- **Full playback control** — play/pause, skip, seek, previous/next, shuffle, repeat
- **Synced lyrics** — pulled from the Music app (embedded) or LRCLIB as a fallback
- **Album art** with colour-extracted gradient backgrounds
- **PWA support** — add to iPhone home screen for a native app feel
- **QR code** in the menu for quick phone connection
- **Custom player** — serve your own HTML page instead of the built-in UI (see [HTML-REFERENCE.md](HTML-REFERENCE.md))

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (to build from source)
- Devices must be on the same Wi-Fi network

## Setup

1. Open `NowPlayingRemote.xcodeproj` in Xcode
2. Select your development team in the project's Signing settings
3. Build and run (`⌘R`)

The app appears in the menu bar. Click the icon to see server status, open the QR code panel, or access Settings.

## Usage

### Connecting from your phone

1. Start the server from the menu bar (auto-starts by default on launch)
2. Open **Show QR Code** and scan it with your phone's camera, or open `http://<your-mac-ip>:8080` in a browser
3. Add to your iPhone home screen via Safari → Share → **Add to Home Screen** for a full-screen experience

### Settings

Open **Settings…** from the menu bar to configure:

| Setting | Default | Description |
|---|---|---|
| Port | 8080 | HTTP listen port |
| Auto-start server | On | Start server on app launch |
| Launch at login | Off | Start app on macOS login |
| Skip interval | 15 s | How far skip forward/back jumps |
| Volume control | Off | Show volume slider in the player |
| Lyrics | On | Fetch and display synced lyrics |
| Custom player | Off | Serve your own HTML page |

## Custom Player

You can replace the built-in player with any HTML page. Go to **Settings → Custom Player** and import an HTML file. The file contents are copied into the app — you can safely delete the original afterwards.

See [HTML-REFERENCE.md](HTML-REFERENCE.md) for the full API (SSE events, endpoints, and commands), and [example.html](example.html) for a minimal working player you can use as a starting point.

## Package dependency

The app uses [`MediaRemoteAdapter`](https://github.com/ejbills/mediaremote-adapter) (fetched from `master`) to interface with macOS's private `MediaRemote.framework`.
