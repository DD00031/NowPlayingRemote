import AppKit

// MARK: - Documentation constant

let customPlayerDocs = """
# Custom Player — API Reference

Replace the built-in web player with any HTML page. Paste your full HTML below \
and click Save. The server will serve it at http://<your-mac>:<port>/.
Click "Reset to Default" to restore the built-in player at any time.

────────────────────────────────────────────────────
SERVER-SENT EVENTS  —  GET /events
────────────────────────────────────────────────────
Connect with:
  const es = new EventSource('/events');
  es.onmessage = e => applyState(JSON.parse(e.data));

Each message is a JSON object with these fields:

  hasMedia          Boolean   — false when nothing is playing
  title             String?
  artist            String?
  album             String?
  isPlaying         Boolean?
  playbackRate      Number?   — 1.0 = normal, 0 = paused
  durationMicros    Number?   — total track length in microseconds
  elapsedTimeMicros Number?   — position at timestampEpochMicros
  timestampEpochMicros Number? — epoch µs when elapsed was snapshotted
  hasArtwork        Boolean
  artworkVersion    Number    — increments when artwork changes; use to decide when to reload /api/artwork
  volume            Number    — 0–100 system output volume
  lyricsVersion     Number    — increments when lyrics change; use to decide when to fetch /api/lyrics
  applicationName   String?   — e.g. "Music", "Spotify"
  shuffleMode       String?   — "off" | "songs" | "albums"
  repeatMode        String?   — "off" | "one" | "all"

Computing live elapsed time:
  function currentElapsed() {
    if (state.timestampEpochMicros == null) return 0;
    const rate  = state.playbackRate ?? 0;
    const base  = (state.elapsedTimeMicros ?? 0) / 1e6;
    const stamp = state.timestampEpochMicros / 1e6;
    return Math.max(0, base + (Date.now() / 1000 - stamp) * rate);
  }

────────────────────────────────────────────────────
ENDPOINTS
────────────────────────────────────────────────────
GET  /api/state
  Same JSON object as SSE (one-shot, useful for initial load).

GET  /api/artwork
  Current album art as PNG. Cache-Control: no-store.
  Only fetch when artworkVersion changes.

GET  /api/lyrics
  {
    found:        Boolean,
    loading:      Boolean,   // true while fetching
    synced:       Boolean,   // true = timestamps available
    instrumental: Boolean,
    source:       "local" | "lrclib",
    lines:        [{ time: Number, text: String }],  // time = seconds; -1 = unsynced
    version:      Number
  }
  Only fetch when lyricsVersion changes.
  Schedule a 25-second retry if loading = true (LRCLIB can be slow).

POST /api/command
  Body: { "command": "<name>", "value": <optional> }
  Commands:
    togglePlayPause
    play
    pause
    nextTrack
    previousTrack
    stop
    skipForward       — skips by the user's configured interval
    skipBackward
    seek              value: seconds (Number)
    setVolume         value: 0–100 (Number)
    toggleShuffle
    toggleRepeat
    setShuffleMode    value: "off" | "songs" | "albums"
    setRepeatMode     value: "off" | "one" | "all"

────────────────────────────────────────────────────
MINIMAL EXAMPLE
────────────────────────────────────────────────────
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <link rel="manifest" href="/manifest.json">
  <link rel="apple-touch-icon" href="/icon-180.png">
</head>
<body>
  <img id="art" src="" style="width:200px;height:200px;object-fit:cover">
  <p id="title"></p>
  <button onclick="cmd('togglePlayPause')">Play / Pause</button>
  <button onclick="cmd('nextTrack')">Next</button>

  <script>
  let artVer = -1;
  const es = new EventSource('/events');
  es.onmessage = e => {
    const s = JSON.parse(e.data);
    document.getElementById('title').textContent = s.title ?? '';
    if (s.hasArtwork && s.artworkVersion !== artVer) {
      artVer = s.artworkVersion;
      document.getElementById('art').src = '/api/artwork?' + Date.now();
    }
  };
  function cmd(command, value) {
    fetch('/api/command', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(value !== undefined ? { command, value } : { command })
    });
  }
  </script>
</body>
</html>
"""

// MARK: - View controller

final class CustomPlayerViewController: NSViewController {

    private let settings: SettingsManager
    private var textView = NSTextView()
    private var docsView = NSTextView()
    private var tabView  = NSTabView()

    init(settings: SettingsManager) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 560))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    private func buildUI() {
        // Tab view
        tabView.frame = NSRect(x: 0, y: 52, width: 700, height: 508)
        tabView.autoresizingMask = [.width, .height]
        view.addSubview(tabView)

        // ── Editor tab ──────────────────────────────────────────
        let editorItem = NSTabViewItem()
        editorItem.label = "Custom HTML"

        let editorScroll = NSScrollView(frame: .zero)
        editorScroll.autoresizingMask = [.width, .height]
        editorScroll.hasVerticalScroller   = true
        editorScroll.hasHorizontalScroller = false
        editorScroll.autohidesScrollers    = true
        editorScroll.borderType = NSBorderType.noBorder

        textView = NSTextView(frame: editorScroll.bounds)
        textView.autoresizingMask    = [.width, .height]
        textView.isEditable          = true
        textView.isRichText          = false
        textView.font                = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor           = .labelColor
        textView.backgroundColor     = NSColor(white: 0.08, alpha: 1)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled  = false
        textView.string = settings.customPlayerHTML ?? ""
        editorScroll.documentView = textView
        editorItem.view = editorScroll
        tabView.addTabViewItem(editorItem)

        // ── Docs tab ─────────────────────────────────────────────
        let docsItem = NSTabViewItem()
        docsItem.label = "API Reference"

        let docsScroll = NSScrollView(frame: .zero)
        docsScroll.autoresizingMask    = [.width, .height]
        docsScroll.hasVerticalScroller = true
        docsScroll.autohidesScrollers  = true
        docsScroll.borderType          = NSBorderType.noBorder

        docsView = NSTextView(frame: docsScroll.bounds)
        docsView.autoresizingMask = [.width, .height]
        docsView.isEditable       = false
        docsView.isRichText       = false
        docsView.font             = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        docsView.textColor        = .labelColor
        docsView.backgroundColor  = NSColor(white: 0.06, alpha: 1)
        docsView.textContainerInset = NSSize(width: 14, height: 14)
        docsView.string           = customPlayerDocs
        docsScroll.documentView   = docsView
        docsItem.view             = docsScroll
        tabView.addTabViewItem(docsItem)

        // ── Bottom bar ───────────────────────────────────────────
        let statusLbl = makeStatusLabel()
        statusLbl.frame = NSRect(x: 20, y: 14, width: 340, height: 18)
        view.addSubview(statusLbl)

        let resetBtn = NSButton(title: "Reset to Default", target: self, action: #selector(resetToDefault))
        resetBtn.frame = NSRect(x: 480, y: 10, width: 130, height: 26)
        resetBtn.bezelStyle = .rounded
        view.addSubview(resetBtn)

        let saveBtn = NSButton(title: "Save & Apply", target: self, action: #selector(saveAndApply))
        saveBtn.frame        = NSRect(x: 576, y: 10, width: 110, height: 26)  // will be re-laid out
        saveBtn.bezelStyle   = .rounded
        saveBtn.keyEquivalent = "\r"
        view.addSubview(saveBtn)

        // Recalculate X positions so buttons sit flush right with 16px margin
        let margin: CGFloat = 16
        let bw1: CGFloat = 130, bw2: CGFloat = 120, gap: CGFloat = 8
        let totalW = view.frame.width
        saveBtn.frame  = NSRect(x: totalW - margin - bw2, y: 10, width: bw2, height: 26)
        resetBtn.frame = NSRect(x: totalW - margin - bw2 - gap - bw1, y: 10, width: bw1, height: 26)
    }

    private func makeStatusLabel() -> NSTextField {
        let lbl = NSTextField(labelWithString: settings.customPlayerHTML != nil
            ? "Custom player active"
            : "Using built-in player")
        lbl.font      = .systemFont(ofSize: 12)
        lbl.textColor = settings.customPlayerHTML != nil ? .systemGreen : .secondaryLabelColor
        return lbl
    }

    @objc private func saveAndApply() {
        let html = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.customPlayerHTML = html.isEmpty ? nil : html
        view.window?.close()
    }

    @objc private func resetToDefault() {
        settings.customPlayerHTML = nil
        textView.string = ""
        view.window?.close()
    }
}
