# Getting Started with Now Playing Remote

Now Playing Remote is a macOS menu-bar app that lets you control media playback from a web browser on any device on your local network.

## Installation

### From Source

1. Clone the repository or download the project files
2. Open `NowPlayingRemote.xcodeproj` in Xcode
3. Build and run the project (⌘R)
4. The app will appear as an icon in your menu bar (top-right corner)

### First Launch

- The app starts a local HTTP server on port `8080` by default
- **Auto-start is enabled by default** — the server will launch whenever you restart your Mac
- Find your Mac's IP address: System Preferences > Network (or run `ifconfig` in Terminal)

## Basic Setup

### 1. Open Settings

Click the **Now Playing Remote** icon in the menu bar and select **Settings** (or press **⌘,**).

### 2. Configure Server Port (Optional)

The default port `8080` works for most people. If you need a different port:
- Settings → Server → Port
- Change the value and restart the server (toggle off/on in Settings)

### 3. Connect a Device

On any device on your network:
1. Open a web browser
2. Navigate to: `http://<your-mac-ip>:8080`
3. The Now Playing player will load

**Finding your Mac's IP:**
- macOS: System Preferences > Network > Advanced > TCP/IP
- Terminal: `ifconfig | grep "inet " | grep -v 127.0.0.1`

## Basic Usage

### Control Playback

The web player shows:
- **Album artwork** (if available)
- **Track info** — title, artist, album
- **Playback controls** — play/pause, skip forward/back
- **Progress bar** — drag to seek

### View Lyrics (if available)

Some themes display lyrics synced to the current track. Lyrics come from:
1. **Embedded in Music app** (if present in the track metadata)
2. **LRCLIB** — automatically fetched from the online lyrics database (requires internet)

Click the **lyrics button** (speech bubble icon) to show/hide the lyrics panel. Once hidden, it stays hidden until you manually re-open it.

### Change Themes

Settings → Custom Player → Theme — select from 10 built-in themes:

| Theme | Best For | Features |
|---|---|---|
| **Clean** | General use | Blurred background, full controls |
| **Immersive** | Focus | Large artwork fill, minimal UI |
| **Minimal** | Simplicity | Text-only, ultra-clean |
| **Vinyl** | Aesthetics | Spinning record animation |
| **Cassette** | Nostalgia | Skeuomorphic cassette design |
| **VHS** | Retro | Scanlines, glitch effects, green text |
| **iPod** | Retro | Click-wheel interface, green LCD |
| **Bento** | Modern | Grid card layout |
| **Starry Sky** | Ambiance | Shooting stars, aurora background |
| **Poster** | Minimalism | Print-design aesthetic |

## Settings Overview

### Server Section
- **Port** — HTTP listen port (default: `8080`)
- **Auto-start server** — launch on login (default: enabled)

### Startup Section
- **Launch at login** — auto-start Now Playing Remote when you restart

### Player Section
- **Show volume control** — volume slider in the web player
- **Show like button** — like/favorite button (app-dependent)
- **Show lyrics** — fetch and display lyrics from Music app / LRCLIB
- **Auto-hide lyrics** — hide panel when no lyrics found (default: enabled)

### Custom Player Section
- **Theme** — select built-in theme or imported `.theme` archive
- **Import custom player** — upload a custom HTML or JavaScript file

## Supported Music Apps

Now Playing Remote works with:
- Apple Music (Music app)
- Spotify
- Apple TV
- Any app using the system MediaRemote framework

## Network Considerations

### Local Network Only
Now Playing Remote only works on your **local network** (same WiFi or Ethernet). It does not expose your server to the internet — that would require additional configuration and is not recommended for security reasons.

### Firewall
If you can't connect from another device, check your Mac's firewall:
- System Preferences > Security & Privacy > Firewall
- If Firewall is enabled, you may need to whitelist the app or disable it for local connections

### iOS / iPadOS
The web player works great on iPhone and iPad. Add it to your home screen:
1. Open Safari to `http://<your-mac-ip>:8080`
2. Tap Share > Add to Home Screen
3. The app will launch in full-screen mode

## Keyboard Shortcuts

- **⌘,** — Open Settings
- **⌘Q** — Quit the app
- Standard media keys (play/pause, etc.) control the current track

## Troubleshooting

**Can't connect to the web player?**
- Verify your Mac's IP address and port number
- Check that both devices are on the same network
- Try disabling your firewall temporarily to test
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

**No lyrics showing?**
- Ensure "Show lyrics" is enabled in Settings
- Music app must have the track loaded
- LRCLIB (online database) requires internet connection
- Some tracks simply don't have lyrics available

**Settings window won't open?**
- Try quitting and relaunching the app
- Check Console.app for error messages
- See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## Next Steps

- **Create a custom theme** — see [THEME_DEVELOPMENT.md](THEME_DEVELOPMENT.md)
- **Customize with JavaScript** — see [HTML-REFERENCE.md](HTML-REFERENCE.md)
- **Build from source** — see [DEVELOPER_SETUP.md](DEVELOPER_SETUP.md)

