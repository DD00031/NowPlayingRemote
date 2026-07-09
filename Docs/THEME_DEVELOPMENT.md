# Theme Development Guide

This guide walks you through creating custom `.theme` archives for Now Playing Remote.

## What is a Theme Archive?

A `.theme` file is a **ZIP archive with a renamed extension**. It contains:
- **theme.json** (required) — metadata
- **styles.css** (required) — custom CSS
- **script.js** (optional) — custom JavaScript
- **assets/** (optional) — images, fonts, SVGs

The archive is extracted to `~/Library/Application Support/NowPlayingRemote/ImportedTheme/` when imported.

## Creating a Theme from Scratch

### Step 1: Create the Directory Structure

```bash
mkdir my-awesome-theme
cd my-awesome-theme

touch theme.json
touch styles.css
touch script.js
mkdir assets
```

### Step 2: Write theme.json

```json
{
  "name": "My Awesome Theme",
  "author": "Your Name",
  "version": "1.0.0",
  "description": "A brief description of your theme",
  "supportsLyrics": true
}
```

**Fields:**
- `name` (required) — displayed in Settings
- `author` (optional) — your name or pseudonym
- `version` (optional) — semantic version string
- `description` (optional) — one-line summary
- `supportsLyrics` (optional) — set `true` if your theme displays lyrics; `false` hides the lyrics button

### Step 3: Build Base HTML (Automatic)

You don't need to create an HTML file. Now Playing Remote generates a base HTML shell with:
- Connection indicator (`#conn-dot`)
- Album artwork area (`.np-artwork-wrap`, `#art`)
- Track info (`.np-info`, `#title`, `#artist`, `#album`)
- Playback controls (`.np-controls`, play/pause/skip buttons)
- Seek bar (`.np-seek`, progress indicator)
- Lyrics panel (if `supportsLyrics: true`)

Your CSS and JS layer on top of this.

### Step 4: Write styles.css

Your CSS is injected after the default layout rules. You can:
- **Override** existing selectors
- **Add new styles** for custom classes you create in JavaScript
- **Use CSS variables** for theme colors and spacing

**Basic example:**

```css
/* Override root colors */
:root {
  --color-bg: #0a0a14;
  --color-text: #ffffff;
  --color-accent: #ff00ff;
}

/* Style the root container */
.np-root {
  background: linear-gradient(135deg, #0a0a14 0%, #1a1a2e 100%);
  color: var(--color-text);
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
  padding: 20px;
}

/* Customize artwork */
.np-artwork-wrap {
  border-radius: 12px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
  max-width: 300px;
  margin: 0 auto;
}

/* Lyrics panel styling */
#lyrics-panel {
  max-height: 200px;
  overflow-y: auto;
  padding: 12px;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 8px;
}

#lyric-lines {
  font-size: 14px;
  line-height: 1.6;
}

#lyric-lines .sync {
  color: var(--color-accent);
  font-weight: 500;
}
```

### Step 5: Write script.js (Optional)

JavaScript runs **after** the base HTML is rendered. You can:
- Listen for state updates
- Animate elements
- Respond to playback changes
- Create custom UI interactions

**Available globals:**

| Global | Signature | Purpose |
|---|---|---|
| `cmd` | `(command: string, value?: number)` | Send a playback command |
| `getState` | `() => StateObject` | Get the current playback state |
| `window.onStateUpdate` | `(state) => void` | Assign this to react to state changes |

**Basic example:**

```js
// Initialize custom UI
const container = document.querySelector('.np-root');
const statusEl = document.createElement('div');
statusEl.id = 'custom-status';
statusEl.style.cssText = 'text-align:center;margin-top:20px;font-size:12px;opacity:0.6;';
container.appendChild(statusEl);

// Update on state change
window.onStateUpdate = function(state) {
  const isPlaying = (state.playbackRate ?? 0) > 0;
  const status = state.hasMedia
    ? (isPlaying ? '▶ Playing' : '⏸ Paused')
    : 'Nothing playing';
  statusEl.textContent = status;

  // Control styling based on state
  if (!state.hasMedia) {
    container.style.opacity = '0.5';
  } else {
    container.style.opacity = '1';
  }
};
```

**Playback commands available:**

```js
cmd('play');                        // Resume playback
cmd('pause');                       // Pause playback
cmd('togglePlayPause');             // Toggle play/pause
cmd('nextTrack');                   // Skip to next
cmd('previousTrack');               // Skip to previous
cmd('skipForward');                 // Skip forward (configured interval)
cmd('skipBackward');                // Skip backward (configured interval)
cmd('seek', 120);                   // Seek to 2 minutes
cmd('setVolume', 50);               // Set volume to 50%
cmd('toggleShuffle');               // Toggle shuffle mode
cmd('toggleRepeat');                // Cycle repeat mode
cmd('setRepeatMode', 'one');        // Set repeat: 'off' | 'one' | 'all'
cmd('setShuffleMode', 'songs');     // Set shuffle: 'off' | 'songs' | 'albums'
```

### Step 6: Add Assets (Optional)

Place images, fonts, SVGs in the `assets/` folder:

```
my-awesome-theme/assets/
├── background.jpg
├── custom-font.woff2
└── icon.svg
```

Reference them in CSS:

```css
@font-face {
  font-family: 'CustomFont';
  src: url('/theme-assets/custom-font.woff2');
}

.np-root {
  background-image: url('/theme-assets/background.jpg');
  font-family: 'CustomFont', sans-serif;
}
```

**Important:** Assets are served at `/theme-assets/<filename>`. Path traversal (`../`) is blocked for security.

## DOM Contract

The base HTML includes these elements you can style/target:

```
.np-root                           Root container
├── #conn-dot                      Connection indicator (small circle)
├── .np-artwork-wrap               Artwork container
│   ├── #art                       Album artwork <img>
│   └── #art-ph                    Placeholder (no artwork)
├── .np-info                       Track information
│   ├── #title                     Track title
│   ├── #artist                    Artist name
│   └── #album                     Album name
├── .np-controls                   Playback controls
│   ├── .np-btn-prev               Previous button
│   ├── .np-btn-play               Play/pause button
│   │   ├── #ico-play              Play icon
│   │   └── #ico-pause             Pause icon
│   └── .np-btn-next               Next button
├── .np-seek                       Progress/seek bar
│   ├── #pb-e                      Elapsed time display
│   ├── input#pb                   Range input for seeking
│   └── #pb-r                      Duration display
└── #lyrics-panel                  Lyrics container (if supportsLyrics)
    ├── #btn-lyrics                Lyrics toggle button
    └── #lyric-lines               Lyrics content
```

## Packaging as a .theme File

Once your theme is ready:

### 1. Create a ZIP file

```bash
cd my-awesome-theme
zip -r ../my-awesome-theme.zip . -x "*.DS_Store"
```

### 2. Rename to .theme

```bash
mv ../my-awesome-theme.zip ../my-awesome-theme.theme
```

### 3. Import into Now Playing Remote

1. Open Now Playing Remote Settings
2. Settings → Custom Player → Theme → Import
3. Select your `.theme` file
4. Review the security warning and confirm
5. The theme is extracted and activated

## Security Considerations

**Important:** Theme archives can execute arbitrary JavaScript. Only install themes from trusted sources.

### For Theme Creators

- **Sign your work** — include your name/contact in theme.json
- **Document dependencies** — list any external fonts or resources
- **Test thoroughly** — verify on multiple macOS versions
- **Avoid sensitive operations** — don't access file system or network (it's sandboxed anyway)

### For Users

- **Verify the source** — only install from creators you trust
- **Review the code** — unzip and inspect theme.json, styles.css, script.js
- **Check the warning** — Now Playing Remote displays a security notice before import
- **One theme at a time** — only one imported theme can be active; replacing it removes the old one

## Theme Examples

### Minimal Theme

```json
{
  "name": "Ultra Minimal",
  "author": "Demo",
  "supportsLyrics": false
}
```

```css
/* Ultra-simple: just title and artist */
.np-root {
  background: #000;
  color: #fff;
  padding: 40px 20px;
  text-align: center;
}

.np-artwork-wrap,
.np-controls,
.np-seek {
  display: none;
}

.np-info {
  font-size: 18px;
}

#title {
  font-weight: bold;
  margin-bottom: 8px;
}

#artist {
  opacity: 0.6;
  font-size: 14px;
}
```

### Interactive Theme with Animation

```js
// Add a spinning icon
const spinner = document.createElement('div');
spinner.id = 'spinner';
spinner.style.cssText = `
  width: 40px;
  height: 40px;
  border: 3px solid rgba(255,255,255,0.3);
  border-top-color: #fff;
  border-radius: 50%;
  margin: 20px auto;
  animation: spin 1s linear infinite;
`;

const style = document.createElement('style');
style.textContent = `
  @keyframes spin {
    to { transform: rotate(360deg); }
  }
`;
document.head.appendChild(style);

document.querySelector('.np-root').appendChild(spinner);

// Control animation on play/pause
window.onStateUpdate = function(state) {
  const isPlaying = (state.playbackRate ?? 0) > 0;
  spinner.style.animationPlayState = isPlaying ? 'running' : 'paused';
};
```

## Debugging Your Theme

1. **Open web inspector** (Safari: ⌘⌥I)
2. **Check the Console tab** for JavaScript errors
3. **Inspect elements** to verify your CSS is applied
4. **Test on different devices** — sizes, orientations, dark mode
5. **Monitor network** — verify assets load from `/theme-assets/`

## Distribution

### Sharing Your Theme

1. Create a GitHub repo or similar
2. Include a `README.md` with:
   - Description and screenshots
   - Installation instructions
   - Credits and license
3. Tag releases with semantic versioning
4. Provide download links to the `.theme` file

### Example README

```markdown
# My Awesome Theme

A beautiful dark theme with custom animations.

## Features
- Dark background with accent colors
- Smooth transitions
- Lyrics support

## Installation
1. Download `my-awesome-theme.theme`
2. Open Now Playing Remote Settings
3. Settings → Custom Player → Theme → Import
4. Select the file

## License
MIT
```

## Troubleshooting

**Theme not showing up?**
- Verify `theme.json` is valid JSON (use a JSON validator)
- Check that the ZIP contains the required files
- Try a simpler theme to isolate the issue

**CSS not applied?**
- Check browser inspector for specificity issues
- Ensure selectors target the correct DOM elements
- Clear your browser cache (⌘⇧Delete in Safari)

**JavaScript errors?**
- Open browser console (⌘⌥I in Safari)
- Check for syntax errors
- Verify function names match the API (e.g., `window.onStateUpdate`)

**Assets not loading?**
- Verify file is in `assets/` folder
- Use `/theme-assets/filename` URL (not relative paths)
- Check that filenames match exactly (case-sensitive)

## Advanced Topics

### Responsive Design

Test your theme at different viewport sizes:

```css
@media (max-width: 480px) {
  .np-root {
    padding: 10px;
  }
  
  .np-artwork-wrap {
    max-width: 200px;
  }
}
```

### Dark Mode Detection

```js
const isDarkMode = window.matchMedia('(prefers-color-scheme: dark)').matches;
```

### Handling No Lyrics

```js
window.onStateUpdate = function(state) {
  const lyricsPanel = document.getElementById('lyrics-panel');
  if (state.lyricsVersion !== undefined) {
    // Lyrics version changed; fetch the latest
    fetch('/api/lyrics').then(r => r.json()).then(data => {
      if (data.found) {
        lyricsPanel.style.display = 'block';
      } else {
        lyricsPanel.style.display = 'none';
      }
    });
  }
};
```

## Resources

- [HTML-REFERENCE.md](HTML-REFERENCE.md) — Complete API documentation
- [Built-in themes](../NowPlayingRemote/ThemePlayer.swift) — Study the source code
- [MDN Web Docs](https://developer.mozilla.org/) — CSS and JavaScript reference

