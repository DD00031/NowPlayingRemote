# Contributing to Now Playing Remote

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to the project.

## Getting Started

### Prerequisites
- macOS 13 (Ventura) or later
- Xcode 15+
- Swift 5.5+
- Git

### Setting Up Your Development Environment

1. **Clone the repository:**
   ```bash
   git clone https://github.com/DD00031/Now-Playing-Remote.git
   cd Now-Playing-Remote
   ```

2. **Open in Xcode:**
   ```bash
   open NowPlayingRemote.xcodeproj
   ```

3. **Build and run:**
   - Select your development team in **Signing & Capabilities**
   - Press **⌘R** to build and run

See [Docs/DEVELOPER_SETUP.md](Docs/DEVELOPER_SETUP.md) for detailed setup instructions.

## How to Contribute

### Reporting Issues

Found a bug? Have a feature request? Please open an issue on GitHub with:

- **Clear title** — briefly describe the problem or feature
- **Detailed description** — explain what you expected vs. what happened
- **Steps to reproduce** — for bugs, provide exact steps
- **System info** — macOS version, app version, relevant hardware details
- **Screenshots/logs** — if applicable, attach images or Console.app logs

### Making Code Changes

#### Before You Start
1. **Create an issue** to discuss major changes first
2. **Check existing pull requests** to avoid duplicate work
3. **Pick an issue** labeled `good first issue` if you're new

#### Development Workflow

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/description-of-change
   ```

2. **Make your changes:**
   - Follow the existing code style (see Code Style section)
   - Keep commits atomic and well-described
   - Test thoroughly on your Mac

3. **Build and test:**
   ```bash
   xcodebuild -project NowPlayingRemote.xcodeproj -scheme NowPlayingRemote build
   ```

4. **Commit and push:**
   ```bash
   git add .
   git commit -m "Brief description of changes"
   git push origin feature/description-of-change
   ```

5. **Create a pull request** on GitHub with:
   - Clear title describing the change
   - Reference to any related issues (`Closes #123`)
   - Summary of what changed and why
   - Testing notes if applicable

### What to Avoid

- **Force pushes** to main or published branches
- **Large monolithic commits** — prefer small, focused commits
- **Breaking changes** without discussion
- **Hard-coded paths or settings** — use UserDefaults and configurable values
- **Unrelated formatting changes** in the same PR as features

## Code Style

### Swift
- **Naming** — descriptive variable and function names
  ```swift
  // Good
  func broadcastStateUpdate() { }
  var mediaController: MediaController
  
  // Avoid
  func broadcast() { }
  var mc: MediaController
  ```

- **Comments** — minimal, only explain WHY not WHAT
  ```swift
  // Good - explains non-obvious intent
  // Increment version only when artwork object changes, not on redundant updates
  artworkVersion = ObjectIdentifier(image).hashValue
  
  // Avoid - obvious from code
  // Set the artwork version
  artworkVersion = version
  ```

- **Spacing** — consistent indentation (4 spaces, no tabs)
- **Force unwrap** — avoid `!` unless you're certain; prefer `guard` or `if let`

### Files
- Place new Swift files in the `NowPlayingRemote/` directory
- Follow existing file organization (no deep nesting)
- Update `project.pbxproj` if adding new files

### Strings and Localization
- Keep user-facing strings concise and clear
- Use `NSLocalizedString` for any user-visible text (prepare for i18n)

## Architecture Guidelines

### General Principles
- **Single responsibility** — each class/struct should do one thing
- **No singletons** where possible; inject dependencies
- **Defensive programming** — validate inputs at system boundaries
- **Avoid premature optimization** — clarity beats micro-optimizations

### POSIX Socket Server (HTTPServer.swift)
The server uses raw sockets rather than a framework. When modifying:
- Respect the three dispatch queues (`acceptQueue`, `handleQueue`, `sseQueue`)
- Keep route handlers small — delegate complex logic to other classes
- Document thread safety for shared state
- Test with multiple concurrent connections

### Themes (ThemePlayer.swift)
When adding or modifying themes:
- Follow the DOM contract (documented in [Docs/THEME_DEVELOPMENT.md](Docs/THEME_DEVELOPMENT.md))
- Test on multiple devices (phones, tablets, desktops)
- Ensure accessibility (color contrast, readable fonts)
- Keep CSS/JS lean — no heavy libraries

### Settings (SettingsViewController.swift, SettingsManager.swift)
- All persisted user settings go through `SettingsManager`
- Use `UserDefaults` keys defined in `SettingsManager.Key`
- Update UI dynamically when settings change
- Test permission prompts on first launch

## Testing

Since there are no automated tests, verify changes manually:

1. **Build the app** — ⌘B
2. **Run the app** — ⌘R
3. **Test the feature** — open `http://localhost:8080` in a browser
4. **Test on another device** — use an iPhone/iPad on the same network
5. **Check edge cases** — no media playing, slow network, theme switching, etc.

### Things to Test
- Playback control (play, pause, skip, seek)
- Artwork loading and updates
- Lyrics fetching and display (Music app and LRCLIB)
- Theme switching
- Settings changes
- Network disconnection/reconnection
- Different Music apps (Music, Spotify, etc.)

## Pull Request Process

1. **Ensure your branch is up to date:**
   ```bash
   git fetch origin
   git rebase origin/main
   ```

2. **Push your branch:**
   ```bash
   git push origin feature/description
   ```

3. **Create a PR on GitHub** with:
   - Clear title and description
   - Reference to related issues
   - Testing notes
   - Any screenshots (if UI changes)

4. **Address review feedback** — respond to comments and make changes as needed

5. **Merge** — once approved, your PR will be merged to `main`

## Documentation

When making changes, update relevant documentation:

- **User-facing changes** → [Docs/GETTING_STARTED.md](Docs/GETTING_STARTED.md)
- **API changes** → [Docs/HTML-REFERENCE.md](Docs/HTML-REFERENCE.md)
- **Architecture changes** → [Docs/CLAUDE.md](Docs/CLAUDE.md) and [Docs/DEVELOPER_SETUP.md](Docs/DEVELOPER_SETUP.md)
- **New features** → relevant doc file and/or README.md
- **Bugs/fixes** → [Docs/TROUBLESHOOTING.md](Docs/TROUBLESHOOTING.md) if applicable

## Commit Messages

Write clear, descriptive commit messages:

```
Brief one-line summary (50 chars max)

Longer explanation if needed. Explain WHY the change was made,
not just WHAT changed. Reference issues if applicable.

Fixes #123
```

Examples:
```
Fix settings window layout conflicts

Settings window failed to open due to Auto Layout constraints.
Changed hugging priority from .required to .defaultLow and
reordered constraint activation for themeWarningNote.

Fixes #45

---

Add lyrics auto-hide timer

When lyrics are loading and panel is open, wait 12s before
hiding instead of closing immediately on track change.
Prevents panel from flashing closed on every song.
```

## Licensing

By contributing, you agree that your changes will be licensed under the project's GPL-3.0 license. See [LICENSE](LICENSE) for details.

## Code of Conduct

- **Be respectful** — treat everyone with courtesy and respect
- **Be constructive** — provide helpful feedback and suggestions
- **Be inclusive** — welcome people of all backgrounds and experience levels
- **Ask questions** — if you're unsure, ask before making major changes

## Getting Help

- **Questions?** — open a discussion on GitHub
- **Stuck?** — check [Docs/TROUBLESHOOTING.md](Docs/TROUBLESHOOTING.md) or existing issues
- **Not sure where to start?** — look for `good first issue` labels

## Recognition

Contributors are acknowledged in:
- The project README.md Acknowledgments section
- Git commit history
- Pull request discussions

Thank you for contributing to make Now Playing Remote better! ❤️

