# Troubleshooting Guide

This guide covers common issues and solutions.

## Connection Issues

### "Can't reach the server" / "Connection refused"

**Symptoms:**
- Browser shows "Cannot connect to http://\<ip\>:8080"
- Connection error when opening the web player

**Causes and solutions:**

1. **Wrong IP address**
   - Verify your Mac's IP address
   - Open Terminal and run: `ifconfig | grep "inet " | grep -v 127.0.0.1`
   - Use the address starting with `192.168.*`, `10.*`, or `172.16-31.*`
   - Not `127.0.0.1` (that's localhost)

2. **Server not running**
   - Check the menu bar — is the Now Playing Remote icon visible?
   - If not, launch the app from Applications
   - Settings → Server → check "Auto-start server" is enabled

3. **Different network**
   - Both devices must be on the **same WiFi network**
   - If one is on 5GHz and one on 2.4GHz, they may not see each other
   - Check: System Preferences > Network

4. **Firewall blocking**
   - System Preferences > Security & Privacy > Firewall > Firewall Options
   - If enabled, add Now Playing Remote to the allowed list OR temporarily disable
   - Try connecting from a device on the same Mac (localhost:8080) to isolate the issue

5. **Port conflict**
   - Another app might be using port 8080
   - Change the port in Settings → Server → Port (try 8081, 8000, etc.)
   - Restart the server after changing the port

### "Connected but no controls work"

**Symptoms:**
- Web player loads but buttons don't respond
- Play/pause doesn't work

**Solutions:**

1. **Check Music app access**
   - Now Playing Remote needs permission to control media
   - System Preferences > Security & Privacy > Automation
   - Ensure Now Playing Remote is allowed for Music app

2. **Music app not running**
   - Launch the Music app (or Spotify, etc.)
   - Start playing a track
   - Try controls again

3. **Browser security restriction**
   - Some browsers block HTTP from HTTPS pages
   - Use `http://` (not `https://`)
   - If the address bar shows a lock, click it and allow insecure content

### Connection drops / SSE stream closes

**Symptoms:**
- Web player works initially, then stops updating
- "Connection lost" message appears

**Solutions:**

1. **WiFi unstable**
   - Move closer to your router
   - Reduce interference (fewer devices, away from microwaves)
   - Try a wired connection if available

2. **Mac went to sleep**
   - System Preferences > Energy Saver
   - Uncheck "Put hard drives to sleep when possible"
   - Set "Computer sleep" to "Never"

3. **Network timeout**
   - The server keeps connections alive with a 25-second ping
   - If your router is aggressive with timeouts, restart the server

## Server Issues

### Settings window won't open

**Symptoms:**
- Click "Settings" in menu or press ⌘, and nothing happens
- Window appears for a moment then disappears

**Solutions:**

1. **Force-quit and restart**
   - Activity Monitor > Now Playing Remote > Force Quit
   - Relaunch the app

2. **Check for crash logs**
   - Open Console.app (Applications > Utilities)
   - Search for "NowPlayingRemote"
   - Look for error messages

3. **Reset preferences**
   - Terminal:
   ```bash
   defaults delete com.apple.dt.Xcode  # or the app's bundle identifier
   ```
   - Restart the app

### App crashes on launch

**Symptoms:**
- App launches then immediately closes
- No error message visible

**Solutions:**

1. **Check Console.app**
   - Applications > Utilities > Console.app
   - Select "Now Playing Remote" in the left sidebar
   - Look for error messages

2. **Remove corrupted settings**
   ```bash
   defaults delete com.apple.dt.Xcode
   ```
   - Restart the app

3. **Rebuild from source**
   - Xcode > Clean Build Folder (⌘⇧K)
   - Xcode > Build (⌘B)
   - Run the app

### Server port won't change

**Symptoms:**
- Change port in Settings, but it reverts
- Error message about port in use

**Solutions:**

1. **Check if port is in use**
   ```bash
   lsof -i :8080  # replace 8080 with your port number
   ```
   - If something is using it, close that app first

2. **Firewall blocking the port**
   - System Preferences > Security & Privacy > Firewall
   - Temporarily disable to test

3. **Restart the server**
   - Settings → Server → toggle off/on
   - Wait a few seconds between toggles

## Player Issues

### No playback controls visible

**Symptoms:**
- Web player loads but shows no buttons
- Only shows track name and artwork

**Solutions:**

1. **Wrong theme selected**
   - Some themes show different controls
   - Settings → Custom Player → Theme → select "Clean" (default)

2. **JavaScript disabled**
   - Check browser settings
   - Safari: Develop > Unchecked Options > Disable JavaScript (should be off)

3. **Refresh the page**
   - Press ⌘R (or Ctrl+R) in the browser
   - Clear cache: ⌘⇧Delete in Safari, Ctrl+Shift+Delete in Chrome

### Artwork not showing

**Symptoms:**
- Album art is blank or shows placeholder
- Other track info displays correctly

**Solutions:**

1. **Artwork in Music app**
   - Open Music app and select the current track
   - If it shows no artwork there, the source doesn't have it
   - Not all tracks have album art available

2. **Browser cache issue**
   - Clear browser cache (⌘⇧Delete in Safari)
   - Refresh the page (⌘R)

3. **App version mismatch**
   - Rebuild the app: Xcode > Clean Build Folder, then Build
   - Restart the app

### Volume control not working

**Symptoms:**
- Volume slider is visible but unresponsive
- Or volume slider not visible at all

**Solutions:**

1. **Check Settings**
   - Settings → Player → "Show volume control" must be enabled

2. **Correct theme**
   - Some themes don't support volume control
   - Switch to "Clean" theme which has full controls

3. **System audio**
   - Verify your Mac's volume is not muted
   - Press F1/F2 or use Control Center to adjust volume manually
   - If that works, try the web player control again

## Lyrics Issues

### No lyrics showing

**Symptoms:**
- Lyrics button is greyed out or missing
- Lyrics panel shows "No lyrics" even for popular songs

**Solutions:**

1. **Check if enabled**
   - Settings → Player → "Show lyrics" must be enabled

2. **Music app embedded lyrics**
   - Open Music app
   - Select current track and check "Info" panel for lyrics
   - If not there, they won't be fetched

3. **LRCLIB fallback**
   - Requires internet connection
   - Check: Can you access `lrclib.net` in a browser?
   - Some songs simply don't have lyrics in the database

4. **Give it time**
   - First lyrics fetch can take 5-10 seconds
   - Wait before concluding they're unavailable

5. **Try a popular song**
   - Play a well-known song (Beatles, Taylor Swift, etc.)
   - These are more likely to have lyrics in LRCLIB

### Lyrics stay visible even when song has none

**Symptoms:**
- Lyrics panel shows old lyrics from previous track
- Or keeps trying to load forever

**Solutions:**

1. **Auto-hide disabled**
   - Settings → Player → "Auto-hide lyrics" should be enabled
   - This automatically hides the panel when no lyrics are found

2. **Manual dismiss**
   - Click the lyrics button (speech bubble) to hide the panel
   - It will stay hidden until you click it again

3. **Different theme**
   - Some themes handle lyrics differently
   - Try the "Clean" theme which has the most robust lyrics support

### Lyrics out of sync

**Symptoms:**
- Lyrics are showing but not on the right beat
- Highlight is on wrong line

**Solutions:**

1. **This is normal for some sources**
   - Lyrics from LRCLIB have varying accuracy
   - Embedded Music app lyrics are usually more accurate

2. **Try a different song**
   - Some tracks have better-synced lyrics than others
   - Popular, recent songs tend to be more accurate

## Theme Issues

### Custom theme won't import

**Symptoms:**
- "Invalid archive" error
- Theme folder appears in Settings but won't activate

**Solutions:**

1. **Check the .theme file structure**
   - Unzip the `.theme` file (double-click to unzip)
   - Verify it contains:
     - `theme.json` (required)
     - `styles.css` (required)
     - `script.js` (optional)
     - `assets/` (optional)
   - All files must be at the root, not in a subfolder

2. **Validate theme.json**
   - Open `theme.json` in a text editor
   - Paste contents into a JSON validator (jsonlint.com)
   - Fix any syntax errors

3. **Re-zip properly**
   - Delete the old .theme file
   - In Terminal:
   ```bash
   cd /path/to/theme/folder
   zip -r ../my-theme.zip . -x "*.DS_Store"
   mv ../my-theme.zip ../my-theme.theme
   ```

4. **Security warning dismissed?**
   - A warning appears before import
   - Make sure you clicked "OK" or "Import", not "Cancel"

### Theme CSS not applying

**Symptoms:**
- Imported theme but colors/styling unchanged
- Theme activates but looks like default

**Solutions:**

1. **CSS selector specificity**
   - Your CSS might have lower specificity than the default
   - Try using `!important`:
   ```css
   .np-root {
     background: #000 !important;
   }
   ```

2. **Browser cache**
   - Refresh with ⌘⇧R (hard refresh, clears cache)
   - Open dev tools (⌘⌥I) and disable cache

3. **Verify CSS was included**
   - Open browser dev tools
   - Right-click an element > Inspect
   - Check the Styles panel for your custom CSS
   - If it's not there, the file may not have been extracted

4. **Check file permissions**
   - Theme is extracted to: `~/Library/Application Support/NowPlayingRemote/ImportedTheme/`
   - Terminal:
   ```bash
   ls -la ~/Library/Application\ Support/NowPlayingRemote/ImportedTheme/
   ```
   - Ensure files are readable

### Theme JavaScript not running

**Symptoms:**
- Custom script.js included but functions don't execute
- Console shows "onStateUpdate is not defined"

**Solutions:**

1. **Syntax errors**
   - Open browser console (⌘⌥I in Safari)
   - Check for JavaScript errors
   - Fix syntax issues in your `script.js`

2. **Global scope**
   - Ensure functions are on `window` object:
   ```js
   // Correct
   window.onStateUpdate = function(state) { ... };
   
   // Wrong (local scope)
   onStateUpdate = function(state) { ... };
   ```

3. **Function not called**
   - `window.onStateUpdate` must be assigned, not declared as a function
   - Use `window.onStateUpdate = function() { }` not `function onStateUpdate() { }`

4. **Check file inclusion**
   - Open dev tools
   - Check Console tab — look for "script.js loaded" messages or errors

### Theme assets not loading

**Symptoms:**
- Background image shows as broken
- Custom fonts not applying
- Assets show 404 errors

**Solutions:**

1. **Check asset paths**
   - Assets must be in an `assets/` subfolder
   - Reference as `/theme-assets/filename` (not relative paths)
   ```css
   /* Correct */
   background-image: url('/theme-assets/bg.jpg');
   
   /* Wrong */
   background-image: url('assets/bg.jpg');
   background-image: url('./bg.jpg');
   ```

2. **Verify files exist**
   - Check the extracted theme folder:
   ```bash
   ls ~/Library/Application\ Support/NowPlayingRemote/ImportedTheme/assets/
   ```

3. **Filename case sensitivity**
   - `/theme-assets/Background.jpg` ≠ `/theme-assets/background.jpg`
   - Use lowercase, no spaces

4. **File size limits**
   - Very large images/fonts may fail to load
   - Compress images and fonts before including

5. **CORS / Security**
   - If using external resources, they must allow requests from your local IP
   - Best practice: bundle all assets in the `.theme` file

## General Troubleshooting

### "Nothing changed" or "App is unresponsive"

**Try these in order:**

1. **Restart the app**
   - Force-quit: ⌘⌥⎋ (or Activity Monitor)
   - Relaunch from Applications

2. **Restart your Mac**
   - Sometimes OS caches cause issues

3. **Rebuild the project**
   ```bash
   xcodebuild -project NowPlayingRemote.xcodeproj -scheme NowPlayingRemote clean build
   ```

4. **Check system logs**
   ```bash
   log stream --predicate 'process == "NowPlayingRemote"'
   ```

5. **Reset preferences**
   ```bash
   defaults delete com.apple.dt.Xcode
   ```

### "Permission denied" errors

**Causes and fixes:**

1. **Media control permission**
   - System Preferences > Security & Privacy > Automation
   - Add Now Playing Remote to the list for Music app

2. **Network port permission**
   - Ports below 1024 require admin privileges
   - Use port 8080 or higher (default is 8080, which works)

3. **File system access**
   - System Preferences > Security & Privacy > Files and Folders
   - If needed, grant access to Preferences folder

### Browser compatibility

**Best experience on:**
- Safari (macOS, iOS)
- Chrome / Edge (macOS, Windows, Android)
- Firefox (cross-platform)

**Known limitations:**
- Internet Explorer — not supported
- Very old browsers — may lack CSS Grid, flexbox support

### Still stuck?

1. **Check Console.app** for detailed error messages
2. **Review [DEVELOPER_SETUP.md](DEVELOPER_SETUP.md)** for technical details
3. **Search GitHub Issues** for similar problems
4. **Create an issue** with:
   - macOS version
   - Music app version
   - Exact error messages
   - Steps to reproduce

