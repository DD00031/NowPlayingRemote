# Custom Player — API Reference

This document covers every API available to a custom HTML player page served by Now Playing Remote.

---

## Connecting — Server-Sent Events (`GET /events`)

The recommended way to receive real-time updates. Open one persistent connection and handle each event as it arrives.

```js
const es = new EventSource('/events');
es.onmessage = e => applyState(JSON.parse(e.data));
es.onerror   = () => { /* reconnect after a delay */ };
```

The server sends the current state immediately on connect, then pushes an event on every change. A `: ping` comment is sent every 25 seconds to keep the connection alive.

### State object fields

| Field | Type | Description |
|---|---|---|
| `hasMedia` | Boolean | `false` when nothing is playing — check this first |
| `title` | String? | Track title |
| `artist` | String? | Artist name |
| `album` | String? | Album name |
| `applicationName` | String? | Source app, e.g. `"Music"`, `"Spotify"` |
| `isPlaying` | Boolean? | Current play/pause state |
| `playbackRate` | Number? | `1.0` = normal speed, `0` = paused |
| `durationMicros` | Number? | Total track length in **microseconds** |
| `elapsedTimeMicros` | Number? | Playback position **at the moment** `timestampEpochMicros` was captured |
| `timestampEpochMicros` | Number? | Epoch time in µs when `elapsedTimeMicros` was snapshotted |
| `hasArtwork` | Boolean | Whether artwork is available |
| `artworkVersion` | Number | Increments whenever the artwork image changes. Use this—not title/artist—to decide when to reload `/api/artwork` |
| `volume` | Number | System output volume, `0`–`100` |
| `lyricsVersion` | Number | Increments whenever lyrics change (loading started, result arrived, or cleared). Use to decide when to fetch `/api/lyrics` |
| `shuffleMode` | String? | `"off"` \| `"songs"` \| `"albums"` |
| `repeatMode` | String? | `"off"` \| `"one"` \| `"all"` |

### Computing live elapsed time

`elapsedTimeMicros` is a snapshot. Extrapolate forward using `playbackRate` and the wall-clock delta:

```js
function currentElapsed() {
  if (state.timestampEpochMicros == null) return 0;
  const rate  = state.playbackRate ?? 0;
  const base  = (state.elapsedTimeMicros ?? 0) / 1e6;   // seconds
  const stamp = state.timestampEpochMicros / 1e6;         // seconds
  return Math.max(0, base + (Date.now() / 1000 - stamp) * rate);
}
```

---

## Endpoints

### `GET /api/state`

Returns the same JSON object as SSE events. Useful for an initial load without opening an SSE connection.

```js
const state = await fetch('/api/state').then(r => r.json());
```

---

### `GET /api/artwork`

Returns the current album art as a PNG.

- `Content-Type: image/png`
- `Cache-Control: no-store`
- Returns `404` when no artwork is available.

**Important:** only reload when `artworkVersion` changes. MediaRemote can fire two updates on a track change — one with the new title/artist and a second one with the updated artwork. Reloading on title change alone will often fetch stale art.

```js
let artworkVer = -1;

function onStateUpdate(s) {
  if (s.hasArtwork && s.artworkVersion !== artworkVer) {
    artworkVer = s.artworkVersion;
    document.getElementById('art').src = '/api/artwork?' + Date.now();
  }
}
```

---

### `GET /api/lyrics`

Returns lyrics for the current track.

```json
{
  "found":        true,
  "loading":      false,
  "synced":       true,
  "instrumental": false,
  "source":       "lrclib",
  "lines": [
    { "time": 12.5, "text": "First lyric line" },
    { "time": 16.0, "text": "Second lyric line" }
  ],
  "version": 3
}
```

| Field | Description |
|---|---|
| `found` | `false` when no lyrics exist for this track |
| `loading` | `true` while the server is still fetching from LRCLIB |
| `synced` | `true` = each line has a timestamp; `false` = plain text only |
| `instrumental` | `true` = track is instrumental (no lyrics expected) |
| `source` | `"local"` (Music app embedded lyrics) or `"lrclib"` |
| `lines[].time` | Seconds from track start; `-1` for unsynced lines |
| `version` | Matches `lyricsVersion` from the state object |

**Usage pattern:** only call this when `lyricsVersion` changes. If `loading` is `true`, schedule a retry after 25 seconds (LRCLIB requests can be slow).

```js
let lyricsVer = -1;
let retryTimer = null;

function onStateUpdate(s) {
  if (s.lyricsVersion !== undefined && s.lyricsVersion !== lyricsVer) {
    lyricsVer = s.lyricsVersion;
    fetchLyrics();
  }
}

function fetchLyrics() {
  clearTimeout(retryTimer);
  fetch('/api/lyrics').then(r => r.json()).then(data => {
    renderLyrics(data);
    if (data.loading) retryTimer = setTimeout(fetchLyrics, 25000);
  });
}
```

---

### `POST /api/command`

Send a playback command.

```js
function cmd(command, value) {
  fetch('/api/command', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(value !== undefined ? { command, value } : { command })
  });
}
```

#### Available commands

| Command | `value` | Description |
|---|---|---|
| `togglePlayPause` | — | Toggle play/pause |
| `play` | — | Play |
| `pause` | — | Pause |
| `stop` | — | Stop |
| `nextTrack` | — | Skip to next track |
| `previousTrack` | — | Skip to previous track |
| `skipForward` | — | Skip forward by the user's configured interval |
| `skipBackward` | — | Skip backward by the user's configured interval |
| `seek` | `Number` (seconds) | Seek to an absolute position |
| `setVolume` | `Number` (0–100) | Set system output volume |
| `toggleShuffle` | — | Cycle shuffle mode |
| `toggleRepeat` | — | Cycle repeat mode |
| `setShuffleMode` | `"off"` \| `"songs"` \| `"albums"` | Set shuffle mode directly |
| `setRepeatMode` | `"off"` \| `"one"` \| `"all"` | Set repeat mode directly |

---

### `GET /manifest.json`

PWA web app manifest. Reference this in your `<head>` to enable "Add to Home Screen" on iOS/Android:

```html
<link rel="manifest" href="/manifest.json">
```

---

### `GET /icon-180.png`

180×180 px app icon PNG. Use as the Apple touch icon:

```html
<link rel="apple-touch-icon" href="/icon-180.png">
```

---

## PWA / iOS Web App tips

To make your custom page feel native when added to the home screen on iOS:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Now Playing">
<meta name="theme-color" content="#0a0a14">
<link rel="manifest" href="/manifest.json">
<link rel="apple-touch-icon" href="/icon-180.png">
```

Use `env(safe-area-inset-*)` with `padding` or `max()` to keep content clear of the notch and home indicator:

```css
.player {
  padding-top:    max(env(safe-area-inset-top), 20px);
  padding-bottom: max(env(safe-area-inset-bottom), 24px);
}
```

Use `position: fixed; inset: 0` on your root container (rather than `height: 100dvh`) to avoid the black bar at the bottom in iOS standalone mode.
