<div align="center">
    <img src="NowPlayingRemote/HomescreenIcon.png" width=200 height=200>
    <h1>Now Playing Remote</h1>
</div>

Control and view your music from any device on your network. Now Playing Remote is a lightweight macOS menu-bar app with a beautiful web player, real-time synced lyrics, and 10 gorgeous built-in themes.

## ✨ Features

- 🎵 **Real-time Media Control** — play/pause, skip, seek, shuffle, repeat from any device
- 🔄 **Instant Updates** — Server-Sent Events push changes immediately (no polling)
- 📱 **Mobile-Optimized Web Player** — responsive design works on phones, tablets, and desktops
- 🎨 **10 Beautiful Built-in Themes** — Clean, Immersive, Vinyl, Cassette, VHS, iPod, Bento, Starry Sky, Minimal, Poster
- 🎤 **Synced Lyrics** — fetched from Music app (embedded) or LRCLIB online database
- 🎨 **Smart Artwork Display** — album art with color-extracted gradient backgrounds
- 📲 **PWA Support** — add to iPhone home screen for a native app experience
- 🔗 **QR Code Quick Connect** — instant access from the menu bar
- 🎯 **Custom Themes** — create and import `.theme` archives with CSS, JavaScript, and custom assets
- ⌨️ **Full Keyboard Support** — media keys control playback

> **Note:** Lyrics from LRCLIB require an internet connection. Embedded Music app lyrics work offline.

> **Note:** Custom `.theme` archives can execute JavaScript — only install themes from trusted sources.

## 🎧 Supported Apps

### Direct Integration
- **Apple Music** (Music app)
- **Spotify**
- **Apple TV**

### Universal Media Control
Works with **any app** using macOS MediaRemote framework:
- YouTube (Safari/Chrome/Firefox)
- VLC Media Player
- QuickTime Player
- Podcasts
- And many more!

## 📦 Installation

**System Requirements:**  
- macOS **13 (Ventura)** or later  
- Xcode 15+ (to build from source)
- Devices must be on the same local network

### Build from Source

1. Clone the repository
2. Open `NowPlayingRemote.xcodeproj` in Xcode
3. Select your development team in **Signing & Capabilities**
4. Build and run (`⌘R`)

The app appears in your menu bar as a note icon. Click it to open settings, show the QR code, or start the server.

> [!IMPORTANT]
>
> On first launch, macOS will request permissions:
> 1. **Accessibility** — required for media key control
> 2. **Automation** (Music) — to control the Music app
> 3. **Automation** (Spotify) — to control Spotify
>
> Grant all permissions for full functionality. The app will work immediately after.

## ⚙️ Setup

### Basic Setup
1. The server starts automatically on app launch (configurable in Settings)
2. Default port is `8080`
3. Find your Mac's IP: **System Preferences → Network** (or run `ifconfig` in Terminal)

### Connect from Your Phone
1. Click the **Now Playing Remote** icon in the menu bar
2. Select **Show QR Code** and scan with your phone's camera
3. Or manually navigate to `http://<your-mac-ip>:8080`
4. **(iOS/iPadOS)** Share → **Add to Home Screen** for a full-screen experience

### Firewall Configuration
If your firewall is enabled and you can't connect:
- **System Preferences → Security & Privacy → Firewall → Firewall Options**
- Add Now Playing Remote to the allowed apps list

## 🎛️ Settings & Customization

### Server Settings
- **Port** — HTTP listen port (default: `8080`)
- **Auto-start server** — launch on app startup (default: enabled)
- **Launch at login** — start app on Mac login (default: disabled)

### Player Settings
- **Show volume control** — display volume slider in web player
- **Show like button** — show like/favorite button (app-dependent)
- **Skip interval** — how far forward/back jumps (default: 15 seconds)
- **Show lyrics** — fetch and display synced lyrics
- **Auto-hide lyrics** — hide panel when no lyrics found (default: enabled)

### Appearance & Customization
- **Theme Selection** — choose from 10 built-in themes
- **Custom Theme Import** — import `.theme` archives
- **Custom HTML/JavaScript** — serve your own web player

## 🎨 Themes

### Built-in Themes
| Theme | Style | Features |
|---|---|---|
| **Clean** (default) | Modern | Blurred background, full controls |
| **Immersive** | Cinematic | Full-screen art fill |
| **Vinyl** | Retro | Spinning record animation |
| **Cassette** | Nostalgic | Skeuomorphic cassette design |
| **VHS** | 80s/90s | Scanlines, glitch effects, phosphor green |
| **iPod Classic** | Retro | Click-wheel interface |
| **Bento** | Modern | Grid card layout |
| **Starry Sky** | Ambient | Shooting stars animation |
| **Minimal** | Minimalist | Text-only, ultra-clean |
| **Poster** | Print-style | Monochrome design |

### Custom Themes
Create a `.theme` archive (renamed ZIP) with:
- `theme.json` — metadata (name, author, version)
- `styles.css` — custom CSS
- `script.js` *(optional)* — custom JavaScript
- `assets/` *(optional)* — images, fonts, SVGs

See [THEME_DEVELOPMENT.md](Docs/THEME_DEVELOPMENT.md) for a complete guide.

## 📚 Documentation

- **[Getting Started](Docs/GETTING_STARTED.md)** — Installation, setup, basic usage
- **[Theme Development](Docs/THEME_DEVELOPMENT.md)** — Create custom themes with code examples
- **[HTML API Reference](Docs/HTML-REFERENCE.md)** — Complete API documentation for custom players
- **[Developer Setup](Docs/DEVELOPER_SETUP.md)** — Build, architecture, debugging
- **[Troubleshooting](Docs/TROUBLESHOOTING.md)** — Common issues and solutions
- **[CLAUDE.md](Docs/CLAUDE.md)** — Architecture deep-dive for developers

## 🔌 Custom Player

Replace the built-in player with your own HTML/JavaScript:

**Settings → Custom Player → Import HTML/JS File…**

Your custom player has access to:
- **Real-time state via SSE** — automatic updates on playback changes
- **Full command API** — send playback commands (play, pause, seek, etc.)
- **Artwork and lyrics** — fetch album art and synced lyrics
- **Helper functions** — `cmd()`, `elapsed()`, `fmt()`, `loadArt()`, `getState()`

See [HTML-REFERENCE.md](Docs/HTML-REFERENCE.md) for the complete API and [DEVELOPER_SETUP.md](Docs/DEVELOPER_SETUP.md) for architecture details.

## 📄 License

Now Playing Remote is available under the GPL-3.0 license. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

Built with assistance from:
- Claude Haiku 4.5
- Claude Sonnet 4.6
- Claude Opus 4.8

Architecture and real-time features powered by:
- [mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter) by ejbills
- POSIX sockets and Server-Sent Events

## ⚠️ Disclaimer

This project is actively developed but provided as-is. While thoroughly tested, it may not receive immediate maintenance for every edge case. Issues and pull requests are welcome — please include your macOS version, app version, and steps to reproduce.

---

<div align="center">
    <p>Made with ❤️ for music lovers</p>
    <p>If you enjoy this app, consider starring the repo! ⭐</p>
</div>
