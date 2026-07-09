# Documentation Index

Welcome to the Now Playing Remote documentation. This folder contains comprehensive guides for users, developers, and theme creators.

## For Users

- **[Getting Started](GETTING_STARTED.md)** — Installation, basic setup, connecting your devices
- **[Troubleshooting](TROUBLESHOOTING.md)** — Common issues and how to fix them

## For Developers

- **[CLAUDE.md](CLAUDE.md)** — Architecture overview, component map, build instructions (for Claude Code)
- **[Developer Setup](DEVELOPER_SETUP.md)** — Setting up your development environment, building from source
- **[HTTP API Reference](HTML-REFERENCE.md)** — Complete API documentation for the web player

## For Theme Creators

- **[Themes Gallery](THEMES.md)** — Showcase of all 10 built-in themes with screenshots
- **[Theme Development Guide](THEME_DEVELOPMENT.md)** — Creating custom `.theme` archives with CSS, JS, and assets

---

## Quick Links

### Server Configuration
- Default port: `8080`
- Default server behavior: automatically starts on app launch
- Configurable in Settings: Server port, auto-start on login

### Playing Media
- Supported apps: Music, Spotify, Apple TV, and any app using MediaRemote
- Control: web interface at `http://<mac-ip>:8080`
- Real-time sync via Server-Sent Events (SSE)

### Themes
- 10 built-in themes included
- Custom `.theme` archives can be imported from Settings
- Each theme can opt into lyrics display, skip controls, volume control

### Lyrics
- Embedded from Music app (AppleScript)
- Fallback to LRCLIB API for online sources
- Auto-hide when not found (configurable)
- Manual dismiss persists across song changes

---

## File Structure

```
Docs/
├── README.md                  (this file)
├── CLAUDE.md                  (for Claude Code)
├── GETTING_STARTED.md         (user guide)
├── DEVELOPER_SETUP.md         (development environment)
├── HTML-REFERENCE.md          (API documentation)
├── THEME_DEVELOPMENT.md       (theme creator guide)
└── TROUBLESHOOTING.md         (FAQ and solutions)
```

---

## Key Concepts

### Server-Sent Events (SSE)
Real-time state updates push from the server to all connected browsers. No polling needed — changes arrive instantly.

### Theme Archives
Packaged as `.theme` files (ZIP with renamed extension). Can contain custom HTML, CSS, JavaScript, and assets.

### UserDefaults Settings
All configuration stored in `~/Library/Preferences/com.apple.dt.Xcode.plist` equivalent for this app. Synced across app restarts.

### Artwork Versioning
The `artworkVersion` integer prevents stale image fetches — only reload `/api/artwork` when this value changes.

---

## Support

For issues or questions:
- Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) first
- Review the relevant section above for your use case
- Verify your network connectivity and app settings

