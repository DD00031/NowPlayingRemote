import Foundation

// MARK: - Theme ID

enum ThemeID: String, CaseIterable {
    case clean     = "clean"
    case immersive = "immersive"
    case poster    = "poster"
    case minimal   = "minimal"
    case vinyl     = "vinyl"
    case cassette  = "cassette"
    case vhs       = "vhs"
    case ipod      = "ipod"
    case bento     = "bento"
    case starry    = "starry"

    var displayName: String {
        switch self {
        case .clean:     return "Clean (Default)"
        case .immersive: return "Immersive"
        case .poster:    return "Poster"
        case .minimal:   return "Minimal"
        case .vinyl:     return "Vinyl"
        case .cassette:  return "Cassette"
        case .vhs:       return "VHS / Late-night"
        case .ipod:      return "iPod Classic"
        case .bento:     return "Bento"
        case .starry:    return "Starry Sky"
        }
    }
}

// MARK: - Entry points

func themeHTML(for theme: ThemeID, settings: SettingsManager) -> String {
    switch theme {
    case .clean:     return cleanHTML(settings)
    case .immersive: return immersiveHTML(settings)
    case .poster:    return posterHTML(settings)
    case .minimal:   return minimalHTML(settings)
    case .vinyl:     return vinylHTML(settings)
    case .cassette:  return cassetteHTML(settings)
    case .vhs:       return vhsHTML(settings)
    case .ipod:      return ipodHTML(settings)
    case .bento:     return bentoHTML(settings)
    case .starry:    return starryHTML(settings)
    }
}

/// Wraps a user-supplied .js file in a minimal PWA HTML shell.
func jsShellHTML(js: String) -> String {
    let safe = js.replacingOccurrences(of: "</script>", with: "<\\/script>")
    return """
    <!DOCTYPE html><html lang="en"><head>
    \(pwaHead())
    </head><body>
    <script>\(safe)</script>
    </body></html>
    """
}

// MARK: - Shared helpers

private func pwaHead(title: String = "Now Playing", color: String = "#0a0a14") -> String {
    """
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="apple-mobile-web-app-title" content="\(title)">
    <meta name="theme-color" content="\(color)">
    <link rel="manifest" href="/manifest.json">
    <link rel="apple-touch-icon" href="/icon-180.png">
    <title>\(title)</title>
    """
}

private let connDotCSS = """
#conn-dot{position:fixed;top:max(env(safe-area-inset-top,0px),10px);right:12px;width:7px;height:7px;border-radius:50%;background:#f44;z-index:9999;transition:background .3s}
#conn-dot.connected{background:#4f4}
#conn-dot.connecting{background:#fa4;animation:_pulse 1s infinite}
@keyframes _pulse{0%,100%{opacity:1}50%{opacity:.3}}
"""

private let rangeCSSWhite = """
input[type=range]{-webkit-appearance:none;appearance:none;width:100%;height:22px;background:transparent;cursor:pointer;outline:none;--fill:0%}
input[type=range]::-webkit-slider-runnable-track{height:3px;border-radius:2px;background:linear-gradient(to right,rgba(255,255,255,.88) var(--fill),rgba(255,255,255,.15) var(--fill))}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:14px;height:14px;border-radius:50%;background:#fff;cursor:pointer;margin-top:-5.5px;box-shadow:0 2px 6px rgba(0,0,0,.5)}
"""

private let rangeCSSBlack = """
input[type=range]{-webkit-appearance:none;appearance:none;width:100%;height:22px;background:transparent;cursor:pointer;outline:none;--fill:0%}
input[type=range]::-webkit-slider-runnable-track{height:3px;border-radius:2px;background:linear-gradient(to right,#111 var(--fill),rgba(0,0,0,.15) var(--fill))}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:14px;height:14px;border-radius:50%;background:#111;cursor:pointer;margin-top:-5.5px}
"""

// Core JS: SSE connection + helpers. Calls window.onStateUpdate(state) on every push.
private let coreJS = """
(function(){
  'use strict';
  let _s={},_eSrc=null,_delay=1000;
  const dot=()=>document.getElementById('conn-dot');
  function _con(){
    if(_eSrc)_eSrc.close();
    if(dot())dot().className='connecting';
    _eSrc=new EventSource('/events');
    _eSrc.onopen=()=>{if(dot())dot().className='connected';_delay=1000};
    _eSrc.onmessage=e=>{try{_s=JSON.parse(e.data);if(window.onStateUpdate)window.onStateUpdate(_s)}catch(_){}};
    _eSrc.onerror=()=>{if(dot())dot().className='';_eSrc.close();_eSrc=null;setTimeout(_con,_delay);_delay=Math.min(_delay*1.5,15000)};
  }
  window.cmd=(c,v)=>{const b={command:c};if(v!==undefined)b.value=v;fetch('/api/command',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)}).catch(()=>{})};
  window.elapsed=()=>{if(_s.timestampEpochMicros==null)return 0;const r=_s.playbackRate??0,base=(_s.elapsedTimeMicros??0)/1e6,stamp=_s.timestampEpochMicros/1e6;return Math.max(0,base+(Date.now()/1000-stamp)*r)};
  window.fmt=s=>{const ss=Math.floor(s),m=Math.floor(ss/60),h=Math.floor(m/60),p=n=>String(n).padStart(2,'0');return h?`${h}:${p(m%60)}:${p(ss%60)}`:`${m}:${p(ss%60)}`};
  window.loadArt=cb=>{const i=new Image();i.crossOrigin='anonymous';i.onload=()=>cb(i);i.src='/api/artwork?'+Date.now()};
  window.getState=()=>_s;
  _con();
})();
"""

// Seek-bar wiring. Assumes <input id="pb"> <span id="pb-e"> <span id="pb-r">
private let seekBarJS = """
(function(){
  const pb=document.getElementById('pb');
  if(!pb)return;
  pb.addEventListener('mousedown',()=>pb._d=true);
  pb.addEventListener('touchstart',()=>pb._d=true,{passive:true});
  pb.addEventListener('change',()=>{
    pb._d=false;
    const s=getState();
    if(s.durationMicros)cmd('seek',(pb.value/1000)*(s.durationMicros/1e6));
  });
  setInterval(()=>{
    const s=getState();if(!s.hasMedia)return;
    const e=elapsed(),d=(s.durationMicros||0)/1e6;
    if(!pb._d){const p=d>0?Math.min(e/d,1):0;pb.value=Math.round(p*1000);pb.style.setProperty('--fill',(p*100)+'%')}
    const eEl=document.getElementById('pb-e'),rEl=document.getElementById('pb-r');
    if(eEl)eEl.textContent=fmt(e);
    if(rEl)rEl.textContent='-'+fmt(Math.max(0,d-e));
  },500);
})();
"""

// MARK: - Clean (Default) ─────────────────────────────────────────────────────

private func cleanHTML(_ settings: SettingsManager) -> String {
    let skipSecs = settings.skipInterval
    let showVol  = settings.showVolumeControl
    let showLyr  = settings.showLyrics
    return """
<!DOCTYPE html>
<html lang="en">
<head>
\(pwaHead())
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --c1: #1a1a2e; --c2: #16213e;
    --accent: #ffffff; --text: #ffffff;
    --text-sub: rgba(255,255,255,0.65);
    --radius: 16px;
    --transition: 0.4s cubic-bezier(0.4,0,0.2,1);
  }

  html, body {
    height: 100vh; overflow: hidden;
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', sans-serif;
    -webkit-font-smoothing: antialiased;
    user-select: none;
    background: #000000;
  }

  #bg {
    position: fixed; top: 0px; left: 0px;
    width: 100vw; height: 100vh;
    background: linear-gradient(160deg, var(--c1) 0%, var(--c2) 100%);
    transition: background var(--transition); z-index: 0;
  }
  #bg::after { content: ''; position: absolute; inset: 0; background: rgba(0,0,0,0.32); }
  #blur-art {
    position: absolute; inset: -40px;
    background-size: cover; background-position: center;
    filter: blur(60px) saturate(1.8);
    opacity: 0; transition: opacity 0.8s ease; transform: scale(1.15);
  }
  #blur-art.visible { opacity: 1; }

  .app-wrap { position: fixed; inset: 0; z-index: 1; display: flex; align-items: stretch; }

  .player-panel {
    flex: 1 0 0; display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    padding: max(env(safe-area-inset-top),20px) 24px max(env(safe-area-inset-bottom),24px);
    max-width: 480px; width: 100%; margin: 0 auto; min-height: 0;
  }

  #artwork-wrap {
    position: relative;
    width: min(54vw, 54vh, 260px); height: min(54vw, 54vh, 260px);
    flex-shrink: 0; margin-bottom: 24px;
    border-radius: 20px; overflow: hidden;
    box-shadow: 0 24px 80px rgba(0,0,0,0.6), 0 8px 24px rgba(0,0,0,0.4);
    transition: transform var(--transition), box-shadow var(--transition);
  }
  #artwork-wrap.playing { transform: scale(1.02); box-shadow: 0 32px 100px rgba(0,0,0,0.7); }
  #artwork { width: 100%; height: 100%; object-fit: cover; display: block; transition: opacity 0.4s; }
  #artwork-placeholder { width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:rgba(255,255,255,0.08);font-size:80px; }

  .track-info { width:100%; text-align:center; margin-bottom:18px; min-height:55px; }
  #title { font-size:clamp(17px,5vw,21px); font-weight:700; color:var(--text); letter-spacing:-0.3px; line-height:1.2; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin-bottom:5px; }
  #artist { font-size:clamp(13px,4vw,15px); color:var(--text-sub); font-weight:500; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  #album { font-size:11px; color:var(--text-sub); opacity:0.65; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin-top:2px; }

  .progress-wrap { width:100%; margin-bottom:14px; }
  \(rangeCSSWhite)
  .time-row { display:flex; justify-content:space-between; font-size:11px; color:var(--text-sub); font-variant-numeric:tabular-nums; font-weight:500; }

  .controls-row { display:flex; align-items:center; justify-content:center; gap:8px; width:100%; margin-bottom:16px; }
  button {
    background:none; border:none; cursor:pointer; color:var(--text);
    display:flex; align-items:center; justify-content:center;
    border-radius:50%; transition:transform 0.12s ease, opacity 0.12s ease, background 0.12s ease;
    -webkit-tap-highlight-color:transparent; touch-action:manipulation; padding:0;
  }
  button:active { transform:scale(0.88); opacity:0.7; }
  .btn-main { width:70px;height:70px; background:rgba(255,255,255,0.14); backdrop-filter:blur(12px); -webkit-backdrop-filter:blur(12px); flex-shrink:0; }
  .btn-main:hover { background:rgba(255,255,255,0.22); }
  .btn-nav  { width:50px;height:50px; opacity:0.85; }
  .btn-skip { width:44px;height:44px; font-size:14px; font-weight:700; opacity:0.75; flex-direction:column; gap:1px; }
  .btn-skip svg { width:22px;height:22px; }

  .volume-row { display:flex;align-items:center;gap:8px;width:100%;padding:0 4px;color:var(--text);opacity:0.8; }
  .btn-vol { width:34px;height:34px;border-radius:50%;flex-shrink:0;color:var(--text);opacity:0.85; }
  .btn-vol:hover { background:rgba(255,255,255,0.12);opacity:1; }
  .btn-vol:active { transform:scale(0.88); }
  .btn-vol svg { width:20px;height:20px;fill:currentColor;pointer-events:none; }
  #volume-slider { flex:1;-webkit-appearance:none;appearance:none;height:22px;background:transparent;outline:none;--vol-fill:50%; }
  #volume-slider::-webkit-slider-runnable-track { height:3px;border-radius:2px;background:linear-gradient(to right,rgba(255,255,255,0.85) var(--vol-fill),rgba(255,255,255,0.2) var(--vol-fill)); }
  #volume-slider::-webkit-slider-thumb { -webkit-appearance:none;width:16px;height:16px;border-radius:50%;background:#fff;cursor:pointer;margin-top:-6.5px;box-shadow:0 2px 6px rgba(0,0,0,0.4); }

  .btn-lyrics-open {
    margin-top: 14px; padding: 7px 22px;
    border: 1px solid rgba(255,255,255,0.22); border-radius: 20px;
    color: rgba(255,255,255,0.72); font-size: 13px; font-weight: 600;
    background: rgba(255,255,255,0.07); letter-spacing: 0.2px;
    transition: background 0.15s ease;
  }
  .btn-lyrics-open:active { background: rgba(255,255,255,0.14); }

  .lyrics-panel {
    position: fixed; inset: 0; z-index: 50;
    background: rgba(8,8,16,0.93);
    backdrop-filter: blur(28px); -webkit-backdrop-filter: blur(28px);
    display: flex; flex-direction: column;
    transform: translateY(100%);
    transition: transform 0.36s cubic-bezier(0.4,0,0.2,1);
  }
  .lyrics-panel.open { transform: translateY(0); }
  .lyrics-panel-header {
    display: flex; align-items: center;
    padding: max(env(safe-area-inset-top,0px),16px) 20px 12px;
    border-bottom: 1px solid rgba(255,255,255,0.08); flex-shrink: 0;
  }
  .lyrics-panel-header h2 { flex:1;font-size:16px;font-weight:700;color:var(--text); }
  .lyrics-source-badge {
    font-size:10px;font-weight:600;letter-spacing:0.6px;text-transform:uppercase;
    color:rgba(255,255,255,0.4);padding:3px 8px;
    border:1px solid rgba(255,255,255,0.15);border-radius:10px;margin-right:10px;
  }
  .btn-close-lyrics { width:30px;height:30px;border-radius:50%;color:rgba(255,255,255,0.6);font-size:18px;background:rgba(255,255,255,0.08); }
  .btn-close-lyrics:hover { background:rgba(255,255,255,0.16); }
  .lyrics-scroll { flex:1;overflow-y:auto;padding:12px 8px max(env(safe-area-inset-bottom),32px);scrollbar-width:none; }
  .lyrics-scroll::-webkit-scrollbar { display:none; }
  .lyric-line { padding:9px 20px;font-size:16px;font-weight:500;color:rgba(255,255,255,0.3);line-height:1.55;text-align:center;border-radius:10px;transition:color 0.25s ease,font-size 0.25s ease;cursor:pointer; }
  .lyric-line:empty::after { content:'♪'; }
  .lyric-line.active { color:rgba(255,255,255,0.95);font-size:19px;font-weight:700; }
  .lyric-line.near-active { color:rgba(255,255,255,0.55); }
  .lyric-line:not(.active):hover { color:rgba(255,255,255,0.55);background:rgba(255,255,255,0.05); }
  .lyrics-status { text-align:center;padding:48px 24px;color:rgba(255,255,255,0.35);font-size:15px;font-weight:500; }

  @media (min-width: 700px) {
    .app-wrap { justify-content: center; align-items: center; }
    .btn-lyrics-open { display: none; }
  }

  \(showLyr ? """
  @media (min-width: 700px) {
    .app-wrap { padding: 32px; gap: 20px; }
    .player-panel { flex: 0 0 300px; max-width: 300px; margin: 0; padding: 28px 24px;
      max-height: min(700px, calc(100vh - 64px)); border-radius: 24px;
      background: rgba(255,255,255,0.05); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255,255,255,0.08); overflow: hidden; }
    #artwork-wrap { width: min(44vw, 44vh, 220px); height: min(44vw, 44vh, 220px); }
    .lyrics-panel { position: static; transform: none; flex: 1; max-width: 440px;
      max-height: min(700px, calc(100vh - 64px)); border-radius: 24px;
      background: rgba(255,255,255,0.04); backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255,255,255,0.08); }
    .lyrics-panel-header { padding: 20px 20px 14px; }
    .lyrics-scroll { padding-bottom: 28px; }
    .btn-close-lyrics { display: none; }
  }
  """ : "")

  \(connDotCSS)

  @media (max-height:600px) {
    #artwork-wrap { width:min(38vw,150px);height:min(38vw,150px);margin-bottom:14px; }
    #title { font-size:15px; } #artist { font-size:12px; }
    .btn-main { width:60px;height:60px; }
  }
</style>
</head>
<body>
<div id="bg"><div id="blur-art"></div></div>
<div id="conn-dot" class="connecting"></div>

<div class="app-wrap">
  <div class="player-panel">
    <div id="artwork-wrap">
      <img id="artwork" src="" alt="" style="display:none">
      <div id="artwork-placeholder">🎵</div>
    </div>
    <div class="track-info">
      <div id="title">Not Playing</div>
      <div id="artist"></div>
      <div id="album"></div>
    </div>
    <div class="progress-wrap">
      <input id="pb" type="range" min="0" max="1000" value="0" step="1">
      <div class="time-row"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
    </div>
    <div class="controls-row">
      <button class="btn-nav" onclick="cmd('previousTrack')" aria-label="Previous">
        <svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg>
      </button>
      <button class="btn-skip" onclick="cmd('skipBackward')" aria-label="Skip back \(skipSecs)s">
        <svg viewBox="0 0 24 24" fill="currentColor"><path d="M11.99 5V1l-5 5 5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6h-2c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/></svg>
        <span style="font-size:10px">\(skipSecs)s</span>
      </button>
      <button class="btn-main" onclick="cmd('togglePlayPause')" aria-label="Play/Pause">
        <svg id="icon-play"  viewBox="0 0 24 24" fill="currentColor" width="30" height="30"><path d="M8 5v14l11-7z"/></svg>
        <svg id="icon-pause" viewBox="0 0 24 24" fill="currentColor" width="30" height="30" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
      </button>
      <button class="btn-skip" onclick="cmd('skipForward')" aria-label="Skip forward \(skipSecs)s">
        <svg viewBox="0 0 24 24" fill="currentColor"><path d="M18 13c0 3.31-2.69 6-6 6s-6-2.69-6-6 2.69-6 6-6v4l5-5-5-5v4c-4.42 0-8 3.58-8 8s3.58 8 8 8 8-3.58 8-8h-2z"/></svg>
        <span style="font-size:10px">\(skipSecs)s</span>
      </button>
      <button class="btn-nav" onclick="cmd('nextTrack')" aria-label="Next">
        <svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg>
      </button>
    </div>
    \(showVol ? """
    <div class="volume-row">
      <button class="btn-vol" onclick="stepVolume(-10)" aria-label="Volume down">
        <svg viewBox="0 0 24 24"><path d="M18.5 12A4.5 4.5 0 0 0 16 7.97v8.05c1.48-.73 2.5-2.25 2.5-4.02zM5 9v6h4l5 5V4L9 9H5zm7-.17v6.34L9.83 13H7v-2h2.83L12 8.83z"/></svg>
      </button>
      <input id="volume-slider" type="range" min="0" max="100" value="80">
      <button class="btn-vol" onclick="stepVolume(10)" aria-label="Volume up">
        <svg viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 7.97v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>
      </button>
    </div>
    """ : "")
    \(showLyr ? "<button class=\"btn-lyrics-open\" onclick=\"toggleLyricsPanel()\" id=\"btn-lyrics-open\">Lyrics</button>" : "")
  </div>

  \(showLyr ? """
  <div id="lyrics-panel" class="lyrics-panel">
    <div class="lyrics-panel-header">
      <h2>Lyrics</h2>
      <span class="lyrics-source-badge" id="lyrics-source"></span>
      <button class="btn-close-lyrics" onclick="toggleLyricsPanel()" aria-label="Close">✕</button>
    </div>
    <div class="lyrics-scroll" id="lyrics-scroll">
      <div id="lyrics-lines"><div class="lyrics-status">Play something to load lyrics</div></div>
    </div>
  </div>
  """ : "")
</div>

<script>
(function() {
  'use strict';
  let lastArtworkVer=-1,lastLyricsVer=-1,lyricData=[],lyricsRetryTimer=null,isDragging=false,progressInterval=null;
  const $=id=>document.getElementById(id);

  window.onStateUpdate = function(s) {
    $('title').textContent  = s.hasMedia ? (s.title||'Unknown Title')  : 'Nothing Playing';
    $('artist').textContent = s.hasMedia ? (s.artist||'') : '';
    $('album').textContent  = s.hasMedia ? (s.album||'')  : '';
    const playing = s.isPlaying||(s.playbackRate>0);
    $('icon-play')  && ($('icon-play').style.display  = playing ? 'none'  : 'block');
    $('icon-pause') && ($('icon-pause').style.display = playing ? 'block' : 'none');
    $('artwork-wrap').classList.toggle('playing', playing&&s.hasMedia);
    if (s.hasArtwork && s.artworkVersion!==lastArtworkVer) {
      lastArtworkVer=s.artworkVersion;
      loadArt(img=>{
        $('artwork').src=img.src; $('artwork').style.display='block'; $('artwork-placeholder').style.display='none';
        $('blur-art').style.backgroundImage=`url('${img.src}')`; $('blur-art').classList.add('visible');
        try {
          const c=document.createElement('canvas');c.width=c.height=60;const ctx=c.getContext('2d');ctx.drawImage(img,0,0,60,60);
          const d=ctx.getImageData(0,0,60,60).data;let r=0,g=0,b=0,n=0;
          for(let i=0;i<d.length;i+=32){r+=d[i];g+=d[i+1];b+=d[i+2];n++}
          r=Math.round(r/n);g=Math.round(g/n);b=Math.round(b/n);
          const lum=0.299*r+0.587*g+0.114*b;if(lum>180){r=Math.round(r*.5);g=Math.round(g*.5);b=Math.round(b*.5)}
          document.documentElement.style.setProperty('--c1',`rgb(${r},${g},${b})`);
          document.documentElement.style.setProperty('--c2',`rgb(${Math.round(r*.5)},${Math.round(g*.5)},${Math.round(b*.5)})`);
        } catch(_){}
      });
    } else if (!s.hasArtwork) {
      lastArtworkVer=-1;
      $('artwork').style.display='none'; $('artwork-placeholder').style.display='flex';
      $('blur-art').classList.remove('visible');
      document.documentElement.style.setProperty('--c1','#1a1a2e');
      document.documentElement.style.setProperty('--c2','#16213e');
    }
    if (s.volume!=null) { const vs=$('volume-slider'); if(vs){vs.value=s.volume;vs.style.setProperty('--vol-fill',s.volume+'%')} }
    if (s.lyricsVersion!==undefined && s.lyricsVersion!==lastLyricsVer) { lastLyricsVer=s.lyricsVersion; fetchLyrics(); }
    if (s.hasMedia) startProgress(); else { stopProgress(); setProgress(0,0); }
  };

  function setProgress(e,d){
    const pct=d>0?Math.min(e/d,1):0;
    if(!isDragging){$('pb').value=Math.round(pct*1000);$('pb').style.setProperty('--fill',(pct*100)+'%')}
    $('pb-e').textContent=fmt(e); $('pb-r').textContent='-'+fmt(Math.max(0,d-e));
  }
  function startProgress(){
    stopProgress();
    progressInterval=setInterval(()=>{if(!getState().hasMedia)return;const s=getState();setProgress(elapsed(),(s.durationMicros||0)/1e6);updateLyricsHighlight(elapsed())},500);
  }
  function stopProgress(){clearInterval(progressInterval);progressInterval=null}

  const pb=$('pb');
  if(pb){
    pb.addEventListener('mousedown',()=>isDragging=true);
    pb.addEventListener('touchstart',()=>isDragging=true,{passive:true});
    pb.addEventListener('change',()=>{isDragging=false;const s=getState();if(s.durationMicros)cmd('seek',(pb.value/1000)*(s.durationMicros/1e6))});
  }

  function fetchLyrics(){
    clearTimeout(lyricsRetryTimer); lyricsRetryTimer=null;
    const panel=$('lyrics-lines'); if(!panel)return;
    fetch('/api/lyrics').then(r=>r.json()).then(data=>{
      renderLyrics(data);
      if(data.loading)lyricsRetryTimer=setTimeout(fetchLyrics,25000);
    }).catch(()=>renderLyricsStatus('Could not load lyrics'));
  }
  function renderLyrics(data){
    const container=$('lyrics-lines'),badge=$('lyrics-source');
    if(!container)return;
    if(data.loading){renderLyricsStatus('Loading lyrics…');lyricData=[];return}
    clearTimeout(lyricsRetryTimer);lyricsRetryTimer=null;
    if(!data.found){renderLyricsStatus('No lyrics found');lyricData=[];if(badge)badge.textContent='';return}
    if(data.instrumental){renderLyricsStatus('♪ Instrumental');lyricData=[];if(badge)badge.textContent='';return}
    lyricData=(data.lines||[]).filter(l=>l.text&&l.text.trim());
    if(badge)badge.textContent=data.source==='local'?'Music app':'LRCLib';
    container.innerHTML=lyricData.map((l,i)=>`<div class="lyric-line" id="ly${i}" data-t="${l.time}" onclick="seekToLyric(${l.time})">${escHtml(l.text)}</div>`).join('');
  }
  function renderLyricsStatus(msg){lyricData=[];const el=$('lyrics-lines');if(el)el.innerHTML=`<div class="lyrics-status">${msg}</div>`}
  function updateLyricsHighlight(e){
    if(!lyricData.length)return;
    let active=-1;
    for(let i=0;i<lyricData.length;i++){if(lyricData[i].time<0||lyricData[i].time<=e)active=i;else break}
    document.querySelectorAll('.lyric-line').forEach((el,i)=>{
      const was=el.classList.contains('active');
      el.classList.toggle('active',i===active);
      el.classList.toggle('near-active',Math.abs(i-active)<=1&&i!==active);
      if(!was&&i===active&&i>=0)el.scrollIntoView({behavior:'smooth',block:'center'});
    });
  }
  window.seekToLyric=t=>{if(t>=0)cmd('seek',t)};
  window.toggleLyricsPanel=()=>$('lyrics-panel')?.classList.toggle('open');

  const vs=$('volume-slider');
  if(vs){
    vs.addEventListener('input',()=>vs.style.setProperty('--vol-fill',vs.value+'%'));
    vs.addEventListener('change',()=>cmd('setVolume',parseInt(vs.value,10)));
    vs.style.setProperty('--vol-fill',vs.value+'%');
  }
  window.stepVolume=delta=>{if(!vs)return;const n=Math.max(0,Math.min(100,parseInt(vs.value,10)+delta));vs.value=n;vs.style.setProperty('--vol-fill',n+'%');cmd('setVolume',n)};

  function escHtml(t){return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')}
})();
\(coreJS)
</script>
</body>
</html>
"""
}

// MARK: - Immersive ───────────────────────────────────────────────────────────

private func immersiveHTML(_ settings: SettingsManager) -> String {
    let skip = settings.skipInterval
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead())
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif;-webkit-font-smoothing:antialiased;user-select:none;background:#000}
#bg{position:fixed;inset:-80px;background-size:cover;background-position:center;filter:blur(90px) saturate(2.8) brightness(0.32);transition:background-image 1s ease,filter 1s ease;z-index:0}
#bg::after{content:'';position:absolute;inset:0;background:radial-gradient(ellipse at 50% 0%,rgba(0,0,0,.1) 0%,rgba(0,0,0,.5) 100%)}
.root{position:fixed;inset:0;z-index:1;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:max(env(safe-area-inset-top),28px) 24px max(env(safe-area-inset-bottom),28px);gap:0}
#art-wrap{width:clamp(200px,min(54vw,54vh),360px);height:clamp(200px,min(54vw,54vh),360px);border-radius:clamp(16px,2vw,24px);overflow:hidden;flex-shrink:0;margin-bottom:clamp(18px,3vh,32px);box-shadow:0 32px 80px rgba(0,0,0,.8),0 8px 24px rgba(0,0,0,.5);transition:transform .4s cubic-bezier(.4,0,.2,1)}
#art-wrap.playing{transform:scale(1.025)}
#art{width:100%;height:100%;object-fit:cover;display:none}
#art-ph{width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:rgba(255,255,255,.07);font-size:72px}
.info{text-align:center;color:#fff;margin-bottom:clamp(14px,2.5vh,24px);width:100%;max-width:clamp(300px,65vw,600px)}
#title{font-size:clamp(18px,3.5vw,32px);font-weight:700;letter-spacing:-.4px;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;line-height:1.2;text-shadow:0 2px 16px rgba(0,0,0,.4)}
#artist{font-size:clamp(13px,2vw,20px);opacity:.72;margin-top:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.prog-wrap{width:100%;max-width:clamp(280px,60vw,560px);margin-bottom:12px}
\(rangeCSSWhite)
.time-row{display:flex;justify-content:space-between;font-size:11px;color:rgba(255,255,255,.5);font-variant-numeric:tabular-nums;margin-top:2px}
.controls{display:flex;align-items:center;justify-content:center;gap:10px}
button{background:none;border:none;cursor:pointer;color:#fff;border-radius:50%;display:flex;align-items:center;justify-content:center;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:transform .12s,opacity .12s;padding:0}
button:active{transform:scale(.88);opacity:.6}
.btn-play{width:70px;height:70px;background:rgba(255,255,255,.18);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px)}
.btn-nav{width:50px;height:50px;opacity:.85}
.btn-skip{width:44px;height:44px;opacity:.7;flex-direction:column;gap:0}
.btn-skip svg{width:22px;height:22px}
.btn-skip span{font-size:9px;font-weight:700;margin-top:-1px}
\(connDotCSS)
@media(max-height:600px){#art-wrap{width:min(36vw,140px);height:min(36vw,140px);margin-bottom:12px}.btn-play{width:58px;height:58px}}
</style></head><body>
<div id="bg"></div>
<div id="conn-dot" class="connecting"></div>
<div class="root">
  <div id="art-wrap"><img id="art" alt=""><div id="art-ph">🎵</div></div>
  <div class="info"><div id="title">Nothing Playing</div><div id="artist"></div></div>
  <div class="prog-wrap">
    <input id="pb" type="range" min="0" max="1000" value="0">
    <div class="time-row"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
  </div>
  <div class="controls">
    <button class="btn-nav" onclick="cmd('previousTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg></button>
    <button class="btn-skip" onclick="cmd('skipBackward')"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M11.99 5V1l-5 5 5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6h-2c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z"/></svg><span>\(skip)s</span></button>
    <button class="btn-play" onclick="cmd('togglePlayPause')">
      <svg id="ico-play" viewBox="0 0 24 24" fill="currentColor" width="30" height="30"><path d="M8 5v14l11-7z"/></svg>
      <svg id="ico-pause" viewBox="0 0 24 24" fill="currentColor" width="30" height="30" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
    </button>
    <button class="btn-skip" onclick="cmd('skipForward')"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M18 13c0 3.31-2.69 6-6 6s-6-2.69-6-6 2.69-6 6-6v4l5-5-5-5v4c-4.42 0-8 3.58-8 8s3.58 8 8 8 8-3.58 8-8h-2z"/></svg><span>\(skip)s</span></button>
    <button class="btn-nav" onclick="cmd('nextTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg></button>
  </div>
</div>
<script>
let _av=-1;
window.onStateUpdate=function(s){
  document.getElementById('title').textContent=s.hasMedia?(s.title||'Unknown'):'Nothing Playing';
  document.getElementById('artist').textContent=s.hasMedia?(s.artist||''):'';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('ico-play').style.display=pl?'none':'block';
  document.getElementById('ico-pause').style.display=pl?'block':'none';
  document.getElementById('art-wrap').classList.toggle('playing',pl&&s.hasMedia);
  if(s.hasArtwork&&s.artworkVersion!==_av){
    _av=s.artworkVersion;
    loadArt(img=>{
      document.getElementById('art').src=img.src;
      document.getElementById('art').style.display='block';
      document.getElementById('art-ph').style.display='none';
      document.getElementById('bg').style.backgroundImage=`url('${img.src}')`;
    });
  } else if(!s.hasArtwork){
    _av=-1;
    document.getElementById('art').style.display='none';
    document.getElementById('art-ph').style.display='flex';
    document.getElementById('bg').style.backgroundImage='';
  }
};
\(seekBarJS)
\(coreJS)
</script></body></html>
"""
}

// MARK: - Poster ──────────────────────────────────────────────────────────────

private func posterHTML(_ settings: SettingsManager) -> String {
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead(color: "#f5f0ec"))
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;-webkit-font-smoothing:antialiased;user-select:none;background:#f5f0ec;color:#111}
.root{position:fixed;inset:0;display:flex;flex-direction:column;justify-content:center;padding:max(env(safe-area-inset-top),32px) clamp(28px,6vw,80px) max(env(safe-area-inset-bottom),32px)}
.eyebrow{font-size:clamp(9px,1vw,11px);font-weight:700;letter-spacing:3px;text-transform:uppercase;color:rgba(0,0,0,.35);margin-bottom:14px}
.main-row{display:flex;align-items:flex-start;gap:clamp(16px,3vw,36px);margin-bottom:20px}
#title{font-size:clamp(32px,8vw,110px);font-weight:900;letter-spacing:-2px;line-height:.92;text-transform:uppercase;flex:1;min-width:0;overflow:hidden;word-break:break-word;filter:grayscale(.15)}
#art-wrap{flex-shrink:0;width:clamp(80px,min(20vw,18vh),180px);height:clamp(80px,min(20vw,18vh),180px);overflow:hidden;border-radius:6px;filter:grayscale(.25) contrast(1.05);box-shadow:4px 4px 0 rgba(0,0,0,.1)}
#art{width:100%;height:100%;object-fit:cover;display:none}
#art-ph{width:100%;height:100%;background:#ddd;display:flex;align-items:center;justify-content:center;font-size:40px}
#artist{font-size:clamp(14px,2.5vw,28px);font-weight:400;letter-spacing:0;color:rgba(0,0,0,.55);margin-bottom:28px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
.divider{height:1px;background:rgba(0,0,0,.12);margin-bottom:20px}
.prog-wrap{margin-bottom:16px}
\(rangeCSSBlack)
.time-row{display:flex;justify-content:space-between;font-size:10px;letter-spacing:.5px;color:rgba(0,0,0,.4);font-variant-numeric:tabular-nums;margin-top:4px}
.controls{display:flex;gap:12px;align-items:center}
button{background:none;border:none;cursor:pointer;color:#111;display:flex;align-items:center;justify-content:center;border-radius:50%;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:transform .12s,opacity .12s;padding:0}
button:active{transform:scale(.88);opacity:.5}
.btn-play{width:56px;height:56px;border:1.5px solid #111;border-radius:50%}
.btn-nav{width:40px;height:40px;opacity:.65}
\(connDotCSS.replacingOccurrences(of: "#f44", with: "#c44").replacingOccurrences(of: "#4f4", with: "#292").replacingOccurrences(of: "#fa4", with: "#c80"))
</style></head><body>
<div id="conn-dot" class="connecting"></div>
<div class="root">
  <div class="eyebrow" id="eyebrow">Now Playing</div>
  <div class="main-row">
    <div id="title">—</div>
    <div id="art-wrap"><img id="art" alt=""><div id="art-ph">♪</div></div>
  </div>
  <div id="artist"></div>
  <div class="divider"></div>
  <div class="prog-wrap">
    <input id="pb" type="range" min="0" max="1000" value="0">
    <div class="time-row"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
  </div>
  <div class="controls">
    <button class="btn-nav" onclick="cmd('previousTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="22" height="22"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg></button>
    <button class="btn-play" onclick="cmd('togglePlayPause')">
      <svg id="ico-play" viewBox="0 0 24 24" fill="currentColor" width="24" height="24"><path d="M8 5v14l11-7z"/></svg>
      <svg id="ico-pause" viewBox="0 0 24 24" fill="currentColor" width="24" height="24" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
    </button>
    <button class="btn-nav" onclick="cmd('nextTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="22" height="22"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg></button>
  </div>
</div>
<script>
let _av=-1;
window.onStateUpdate=function(s){
  document.getElementById('title').textContent=s.hasMedia?(s.title||'UNKNOWN'):'NOTHING PLAYING';
  document.getElementById('artist').textContent=s.hasMedia?(s.artist||''):'';
  document.getElementById('eyebrow').textContent=s.hasMedia?(s.album||'Now Playing'):'Now Playing';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('ico-play').style.display=pl?'none':'block';
  document.getElementById('ico-pause').style.display=pl?'block':'none';
  if(s.hasArtwork&&s.artworkVersion!==_av){
    _av=s.artworkVersion;
    loadArt(img=>{document.getElementById('art').src=img.src;document.getElementById('art').style.display='block';document.getElementById('art-ph').style.display='none'});
  } else if(!s.hasArtwork){_av=-1;document.getElementById('art').style.display='none';document.getElementById('art-ph').style.display='flex'}
};
\(seekBarJS)
\(coreJS)
</script></body></html>
"""
}

// MARK: - Minimal ─────────────────────────────────────────────────────────────

private func minimalHTML(_ settings: SettingsManager) -> String {
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead(color: "#0e0e0e"))
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif;-webkit-font-smoothing:antialiased;user-select:none;background:#0e0e0e;color:#fff}
.root{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:max(env(safe-area-inset-top),32px) clamp(32px,6vw,80px) max(env(safe-area-inset-bottom),32px);gap:0}
#title{font-size:clamp(20px,4vw,40px);font-weight:600;letter-spacing:-.5px;text-align:center;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;width:100%;max-width:clamp(300px,65vw,680px);margin-bottom:8px;line-height:1.15}
#artist{font-size:clamp(13px,2vw,20px);color:rgba(255,255,255,.4);font-weight:400;text-align:center;width:100%;max-width:clamp(300px,65vw,680px);overflow:hidden;white-space:nowrap;text-overflow:ellipsis;margin-bottom:clamp(24px,4vh,48px)}
.prog-wrap{width:100%;max-width:clamp(280px,60vw,620px);margin-bottom:clamp(24px,4vh,48px)}
.prog-track{height:2px;background:rgba(255,255,255,.08);border-radius:1px;position:relative;cursor:pointer}
.prog-fill{height:100%;background:rgba(255,255,255,.8);border-radius:1px;width:0%;transition:width .5s linear}
.time-row{display:flex;justify-content:space-between;font-size:10px;color:rgba(255,255,255,.25);font-variant-numeric:tabular-nums;margin-top:10px;letter-spacing:.3px}
.controls{display:flex;align-items:center;gap:28px}
button{background:none;border:none;cursor:pointer;color:rgba(255,255,255,.7);display:flex;align-items:center;justify-content:center;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:opacity .12s,transform .12s;padding:0}
button:active{transform:scale(.88);opacity:.4}
.btn-play{width:48px;height:48px;color:#fff;border:1px solid rgba(255,255,255,.2);border-radius:50%}
.btn-nav{width:36px;height:36px;opacity:.55}
\(connDotCSS)
</style></head><body>
<div id="conn-dot" class="connecting"></div>
<div class="root">
  <div id="title">Nothing Playing</div>
  <div id="artist"></div>
  <div class="prog-wrap">
    <div class="prog-track" id="prog-track">
      <div class="prog-fill" id="prog-fill"></div>
    </div>
    <div class="time-row"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
  </div>
  <div class="controls">
    <button class="btn-nav" onclick="cmd('previousTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="22" height="22"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg></button>
    <button class="btn-play" onclick="cmd('togglePlayPause')">
      <svg id="ico-play" viewBox="0 0 24 24" fill="currentColor" width="22" height="22"><path d="M8 5v14l11-7z"/></svg>
      <svg id="ico-pause" viewBox="0 0 24 24" fill="currentColor" width="22" height="22" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
    </button>
    <button class="btn-nav" onclick="cmd('nextTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="22" height="22"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg></button>
  </div>
</div>
<script>
let _pct=0,_dur=0;
window.onStateUpdate=function(s){
  document.getElementById('title').textContent=s.hasMedia?(s.title||'Unknown'):'Nothing Playing';
  document.getElementById('artist').textContent=s.hasMedia?(s.artist||''):'';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('ico-play').style.display=pl?'none':'block';
  document.getElementById('ico-pause').style.display=pl?'block':'none';
  _dur=(s.durationMicros||0)/1e6;
};
const track=document.getElementById('prog-track');
let _seeking=false,_seekX=0;
if(track){
  const seek=e=>{
    const r=track.getBoundingClientRect(),x=(e.touches?e.touches[0].clientX:e.clientX)-r.left;
    const pct=Math.max(0,Math.min(1,x/r.width));
    document.getElementById('prog-fill').style.width=(pct*100)+'%';
    if(_dur)cmd('seek',pct*_dur);
  };
  track.addEventListener('click',seek);
  track.addEventListener('touchend',e=>{e.preventDefault();seek(e.changedTouches[0]?{touches:[e.changedTouches[0]]}:e)},{passive:false});
}
setInterval(()=>{
  const s=getState();if(!s.hasMedia)return;
  const e=elapsed(),d=_dur||0;
  const pct=d>0?Math.min(e/d,1):0;
  document.getElementById('prog-fill').style.width=(pct*100)+'%';
  const eEl=document.getElementById('pb-e'),rEl=document.getElementById('pb-r');
  if(eEl)eEl.textContent=fmt(e);if(rEl)rEl.textContent='-'+fmt(Math.max(0,d-e));
},500);
\(coreJS)
</script></body></html>
"""
}

// MARK: - Vinyl ───────────────────────────────────────────────────────────────

private func vinylHTML(_ settings: SettingsManager) -> String {
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead(color: "#0d0d0d"))
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif;-webkit-font-smoothing:antialiased;user-select:none;background:#0d0d0d;color:#fff}
.root{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:max(env(safe-area-inset-top),20px) 24px max(env(safe-area-inset-bottom),20px);gap:0}
/* Platter shadow */
.platter{position:relative;margin-bottom:28px;flex-shrink:0}
.platter::after{content:'';position:absolute;bottom:-18px;left:50%;transform:translateX(-50%);width:88%;height:24px;background:radial-gradient(ellipse,rgba(0,0,0,.6) 0%,transparent 70%);border-radius:50%;filter:blur(6px)}
/* Disc */
#disc{width:clamp(200px,min(60vw,60vh),380px);height:clamp(200px,min(60vw,60vh),380px);border-radius:50%;position:relative;overflow:hidden;
  box-shadow:0 0 0 10px #1a1a1a,0 0 0 12px #111,0 0 0 22px #1c1c1c,0 12px 40px rgba(0,0,0,.9);
  animation:_spin 4s linear infinite;animation-play-state:paused}
.playing #disc{animation-play-state:running}
@keyframes _spin{to{transform:rotate(360deg)}}
#art{width:100%;height:100%;object-fit:cover;display:none}
#art-ph{width:100%;height:100%;background:radial-gradient(circle at 50%,#2a2a2a,#111);display:flex;align-items:center;justify-content:center;font-size:60px;opacity:.4}
/* Center label overlay */
#disc-label{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:36%;height:36%;border-radius:50%;background:#0d0d0d;border:2px solid #222;display:flex;align-items:center;justify-content:center}
#disc-label::before{content:'';position:absolute;width:10px;height:10px;border-radius:50%;background:#333;border:1.5px solid #444}
/* Grooves overlay */
#disc::before{content:'';position:absolute;inset:0;background:repeating-radial-gradient(circle at 50%,transparent 0px,transparent 5px,rgba(0,0,0,.12) 5.5px,rgba(0,0,0,.12) 6px);border-radius:50%;pointer-events:none;z-index:1}
/* Info */
.info{text-align:center;margin-bottom:18px;width:100%;max-width:clamp(300px,60vw,540px)}
#title{font-size:clamp(16px,3vw,28px);font-weight:600;letter-spacing:-.2px;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;line-height:1.2}
#artist{font-size:clamp(13px,1.8vw,18px);color:rgba(255,255,255,.45);margin-top:5px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
/* Progress */
.prog-wrap{width:100%;max-width:clamp(280px,55vw,500px);margin-bottom:14px}
\(rangeCSSWhite)
.time-row{display:flex;justify-content:space-between;font-size:10px;color:rgba(255,255,255,.3);font-variant-numeric:tabular-nums;margin-top:2px}
/* Controls */
.controls{display:flex;align-items:center;gap:12px}
button{background:none;border:none;cursor:pointer;color:#fff;border-radius:50%;display:flex;align-items:center;justify-content:center;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:transform .12s,opacity .12s;padding:0}
button:active{transform:scale(.88);opacity:.6}
.btn-play{width:64px;height:64px;background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.12)}
.btn-nav{width:46px;height:46px;opacity:.75}
\(connDotCSS)
@media(max-height:580px){#disc{width:clamp(150px,45vh,220px);height:clamp(150px,45vh,220px)}}
</style></head><body>
<div id="conn-dot" class="connecting"></div>
<div class="root" id="root">
  <div class="platter">
    <div id="disc">
      <img id="art" alt="">
      <div id="art-ph">♪</div>
      <div id="disc-label"></div>
    </div>
  </div>
  <div class="info"><div id="title">Nothing Playing</div><div id="artist"></div></div>
  <div class="prog-wrap">
    <input id="pb" type="range" min="0" max="1000" value="0">
    <div class="time-row"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
  </div>
  <div class="controls">
    <button class="btn-nav" onclick="cmd('previousTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="26" height="26"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg></button>
    <button class="btn-play" onclick="cmd('togglePlayPause')">
      <svg id="ico-play" viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M8 5v14l11-7z"/></svg>
      <svg id="ico-pause" viewBox="0 0 24 24" fill="currentColor" width="28" height="28" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
    </button>
    <button class="btn-nav" onclick="cmd('nextTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="26" height="26"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg></button>
  </div>
</div>
<script>
let _av=-1;
window.onStateUpdate=function(s){
  document.getElementById('title').textContent=s.hasMedia?(s.title||'Unknown'):'Nothing Playing';
  document.getElementById('artist').textContent=s.hasMedia?(s.artist||''):'';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('ico-play').style.display=pl?'none':'block';
  document.getElementById('ico-pause').style.display=pl?'block':'none';
  document.getElementById('root').classList.toggle('playing',pl&&s.hasMedia);
  if(s.hasArtwork&&s.artworkVersion!==_av){
    _av=s.artworkVersion;
    loadArt(img=>{document.getElementById('art').src=img.src;document.getElementById('art').style.display='block';document.getElementById('art-ph').style.display='none'});
  } else if(!s.hasArtwork){_av=-1;document.getElementById('art').style.display='none';document.getElementById('art-ph').style.display='flex'}
};
\(seekBarJS)
\(coreJS)
</script></body></html>
"""
}

// MARK: - Cassette ────────────────────────────────────────────────────────────

private func cassetteHTML(_ settings: SettingsManager) -> String {
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead(color: "#f0e8d5"))
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif;-webkit-font-smoothing:antialiased;user-select:none;background:#f0e8d5;color:#2a1e0f}
.root{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:max(env(safe-area-inset-top),20px) 20px max(env(safe-area-inset-bottom),20px);gap:20px}
/* Cassette body */
.cassette{position:relative;width:clamp(280px,min(90vw,65vh),460px);height:clamp(170px,min(55vw,40vh),285px);background:linear-gradient(170deg,#3a2a1a 0%,#2a1e0f 100%);border-radius:8px;box-shadow:0 12px 40px rgba(0,0,0,.35),0 2px 0 rgba(255,255,255,.08) inset;flex-shrink:0}
/* Notch at top */
.cassette::before{content:'';position:absolute;top:0;left:50%;transform:translateX(-50%);width:40%;height:10px;background:#f0e8d5;border-radius:0 0 8px 8px}
/* Tape window */
.tape-window{position:absolute;top:50%;left:50%;transform:translate(-50%,-45%);width:80%;height:60%;background:#111;border-radius:4px;overflow:hidden;display:flex;align-items:center;justify-content:space-around;padding:8px 12px}
/* Reels */
.reel{width:min(18vw,65px);height:min(18vw,65px);border-radius:50%;position:relative;overflow:hidden;
  background:conic-gradient(from 0deg,#1a1a1a 0%,#2a2a2a 16.7%,#1a1a1a 16.7%,#1a1a1a 33.3%,#2a2a2a 33.3%,#2a2a2a 50%,#1a1a1a 50%,#1a1a1a 66.7%,#2a2a2a 66.7%,#2a2a2a 83.3%,#1a1a1a 83.3%,#1a1a1a 100%);
  box-shadow:0 0 0 2px #333 inset;
  animation:_reel 1.8s linear infinite;animation-play-state:paused}
.playing .reel{animation-play-state:running}
.reel-hub{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:30%;height:30%;border-radius:50%;background:#2a2a2a;border:2px solid #444}
@keyframes _reel{to{transform:rotate(360deg)}}
/* Label */
.cassette-label{position:absolute;bottom:6px;left:50%;transform:translateX(-50%);width:40%;background:#f0e8d5;border-radius:3px;padding:4px 8px;text-align:center}
.label-brand{font-size:8px;font-weight:800;letter-spacing:2px;text-transform:uppercase;color:rgba(42,30,15,.4);margin-bottom:2px}
.label-title{font-size:9px;font-weight:700;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;color:#2a1e0f}
.label-artist{font-size:8px;color:rgba(42,30,15,.55);overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
/* Screws */
.cassette::after{content:'• •';position:absolute;bottom:8px;left:0;right:0;text-align:center;font-size:18px;letter-spacing:40px;color:rgba(255,255,255,.12);padding-left:40px}
/* Info below cassette */
.info{text-align:center;max-width:clamp(280px,min(90vw,65vh),460px);width:100%}
#title{font-size:clamp(16px,3vw,28px);font-weight:700;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;margin-bottom:4px;line-height:1.2}
#artist{font-size:clamp(13px,1.8vw,18px);color:rgba(42,30,15,.5);overflow:hidden;white-space:nowrap;text-overflow:ellipsis;margin-bottom:16px}
/* Progress */
.prog-wrap{width:100%;max-width:clamp(280px,min(90vw,65vh),460px)}
\(rangeCSSBlack)
.time-row{display:flex;justify-content:space-between;font-size:10px;color:rgba(42,30,15,.4);font-variant-numeric:tabular-nums;margin-top:4px}
/* Controls */
.controls{display:flex;gap:16px;align-items:center}
button{background:none;border:none;cursor:pointer;color:#2a1e0f;border-radius:50%;display:flex;align-items:center;justify-content:center;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:transform .12s,opacity .12s;padding:0}
button:active{transform:scale(.88);opacity:.5}
.btn-play{width:56px;height:56px;border:1.5px solid rgba(42,30,15,.3);border-radius:50%}
.btn-nav{width:40px;height:40px;opacity:.6}
\(connDotCSS.replacingOccurrences(of: "#f44", with: "#c44").replacingOccurrences(of: "#4f4", with: "#484").replacingOccurrences(of: "#fa4", with: "#c80"))
</style></head><body>
<div id="conn-dot" class="connecting"></div>
<div class="root" id="root">
  <div class="cassette">
    <div class="tape-window">
      <div class="reel"><div class="reel-hub"></div></div>
      <div class="reel"><div class="reel-hub"></div></div>
    </div>
    <div class="cassette-label">
      <div class="label-brand">Now Playing</div>
      <div class="label-title" id="lbl-title">—</div>
      <div class="label-artist" id="lbl-artist"></div>
    </div>
  </div>
  <div class="info">
    <div id="title">Nothing Playing</div>
    <div id="artist"></div>
  </div>
  <div class="prog-wrap">
    <input id="pb" type="range" min="0" max="1000" value="0">
    <div class="time-row"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
  </div>
  <div class="controls">
    <button class="btn-nav" onclick="cmd('previousTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="24" height="24"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg></button>
    <button class="btn-play" onclick="cmd('togglePlayPause')">
      <svg id="ico-play" viewBox="0 0 24 24" fill="currentColor" width="24" height="24"><path d="M8 5v14l11-7z"/></svg>
      <svg id="ico-pause" viewBox="0 0 24 24" fill="currentColor" width="24" height="24" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
    </button>
    <button class="btn-nav" onclick="cmd('nextTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="24" height="24"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg></button>
  </div>
</div>
<script>
window.onStateUpdate=function(s){
  document.getElementById('title').textContent=s.hasMedia?(s.title||'Unknown'):'Nothing Playing';
  document.getElementById('artist').textContent=s.hasMedia?(s.artist||''):'';
  document.getElementById('lbl-title').textContent=s.hasMedia?(s.title||'Unknown'):'—';
  document.getElementById('lbl-artist').textContent=s.hasMedia?(s.artist||''):'';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('ico-play').style.display=pl?'none':'block';
  document.getElementById('ico-pause').style.display=pl?'block':'none';
  document.getElementById('root').classList.toggle('playing',pl&&s.hasMedia);
};
\(seekBarJS)
\(coreJS)
</script></body></html>
"""
}

// MARK: - VHS ─────────────────────────────────────────────────────────────────

private func vhsHTML(_ settings: SettingsManager) -> String {
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead(color: "#050a05"))
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:'Courier New',Courier,monospace;-webkit-font-smoothing:none;user-select:none;background:#050a05;color:#33ff55}
/* Scanlines */
body::after{content:'';position:fixed;inset:0;background:repeating-linear-gradient(0deg,transparent,transparent 3px,rgba(0,0,0,.18) 3px,rgba(0,0,0,.18) 4px);pointer-events:none;z-index:9998}
/* CRT vignette */
body::before{content:'';position:fixed;inset:0;background:radial-gradient(ellipse at 50% 50%,transparent 60%,rgba(0,0,0,.55) 100%);pointer-events:none;z-index:9997}
.root{position:fixed;inset:0;display:flex;flex-direction:column;justify-content:center;padding:max(env(safe-area-inset-top),28px) clamp(24px,5vw,80px) max(env(safe-area-inset-bottom),28px);gap:0;z-index:1}
/* VHS header */
.vhs-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:20px;opacity:.7;font-size:clamp(10px,1.2vw,14px);letter-spacing:1px}
#vhs-ch{font-size:clamp(12px,1.5vw,16px);font-weight:700}
/* Track info */
.track-block{margin-bottom:clamp(18px,3vh,32px)}
.vhs-label{font-size:clamp(9px,1vw,11px);letter-spacing:2px;text-transform:uppercase;color:rgba(51,255,85,.4);margin-bottom:6px}
#title{font-size:clamp(20px,5vw,56px);font-weight:700;letter-spacing:-.5px;line-height:1;overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;margin-bottom:8px;animation:_glitch 8s infinite}
@keyframes _glitch{
  0%,96%,100%{transform:none;color:#33ff55;text-shadow:none}
  97%{transform:skewX(-1.5deg);color:#55ffcc;text-shadow:-1px 0 #ff0055,1px 0 #0055ff}
  98%{transform:none;color:#33ff55;text-shadow:none}
  99%{transform:skewX(1deg) translateX(2px);color:#ff3355;text-shadow:none}
}
#artist{font-size:clamp(13px,2.2vw,22px);color:rgba(51,255,85,.6);letter-spacing:1px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
/* Progress */
.prog-wrap{margin-bottom:20px}
.prog-track{height:2px;background:rgba(51,255,85,.15);position:relative;cursor:pointer;margin-bottom:6px}
.prog-fill{height:100%;background:#33ff55;box-shadow:0 0 8px #33ff55;width:0%}
.time-row{display:flex;justify-content:space-between;font-size:10px;color:rgba(51,255,85,.45);font-variant-numeric:tabular-nums;letter-spacing:1px}
/* Controls */
.controls{display:flex;gap:20px;align-items:center}
button{background:none;border:1px solid rgba(51,255,85,.25);cursor:pointer;color:#33ff55;border-radius:2px;display:flex;align-items:center;justify-content:center;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:opacity .12s,background .12s;padding:0;font-family:inherit}
button:active{opacity:.5;background:rgba(51,255,85,.1)}
.btn-play{width:60px;height:36px;font-size:11px;letter-spacing:1px}
.btn-nav{width:40px;height:36px;font-size:9px;letter-spacing:1px}
/* Timestamp */
#vhs-time{font-size:12px;font-weight:700;letter-spacing:1px}
/* Conn dot override */
\(connDotCSS.replacingOccurrences(of: "#f44", with: "#ff0055").replacingOccurrences(of: "#4f4", with: "#33ff55").replacingOccurrences(of: "#fa4", with: "#ffaa00"))
#conn-dot{width:6px;height:6px;top:max(env(safe-area-inset-top,0px),10px)}
</style></head><body>
<div id="conn-dot" class="connecting"></div>
<div class="root">
  <div class="vhs-header">
    <span id="vhs-ch">▶ CH 01</span>
    <span id="vhs-time">00:00:00</span>
  </div>
  <div class="track-block">
    <div class="vhs-label">Now Playing</div>
    <div id="title">—</div>
    <div id="artist"></div>
  </div>
  <div class="prog-wrap">
    <div class="prog-track" id="prog-track"><div class="prog-fill" id="prog-fill"></div></div>
    <div class="time-row"><span id="pb-e">00:00</span><span id="pb-r">00:00</span></div>
  </div>
  <div class="controls">
    <button class="btn-nav" onclick="cmd('previousTrack')">◀◀</button>
    <button class="btn-play" onclick="cmd('togglePlayPause')" id="btn-pp">▶ PLAY</button>
    <button class="btn-nav" onclick="cmd('nextTrack')">▶▶</button>
  </div>
</div>
<script>
let _dur=0;
window.onStateUpdate=function(s){
  document.getElementById('title').textContent=s.hasMedia?(s.title||'UNKNOWN'):'— NO SIGNAL —';
  document.getElementById('artist').textContent=s.hasMedia?(s.artist||''):'';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('btn-pp').textContent=pl?'▮▮ PAUSE':'▶ PLAY';
  document.getElementById('vhs-ch').textContent=pl?'▶ CH 01':'■ CH 01';
  _dur=(s.durationMicros||0)/1e6;
};
const track=document.getElementById('prog-track');
if(track)track.addEventListener('click',e=>{const r=track.getBoundingClientRect();const p=(e.clientX-r.left)/r.width;if(_dur)cmd('seek',Math.max(0,Math.min(1,p))*_dur)});
// Clock
setInterval(()=>{
  const now=new Date();
  document.getElementById('vhs-time').textContent=String(now.getHours()).padStart(2,'0')+':'+String(now.getMinutes()).padStart(2,'0')+':'+String(now.getSeconds()).padStart(2,'0');
},1000);
// Progress
setInterval(()=>{
  const s=getState();if(!s.hasMedia)return;
  const e=elapsed(),d=_dur||0;
  const p=d>0?Math.min(e/d,1):0;
  document.getElementById('prog-fill').style.width=(p*100)+'%';
  const eEl=document.getElementById('pb-e'),rEl=document.getElementById('pb-r');
  const f=t=>{const s=Math.floor(t),m=Math.floor(s/60);return String(m).padStart(2,'0')+':'+String(s%60).padStart(2,'0')};
  if(eEl)eEl.textContent=f(e);if(rEl)rEl.textContent=f(Math.max(0,d-e));
},500);
\(coreJS)
</script></body></html>
"""
}

// MARK: - iPod Classic ────────────────────────────────────────────────────────

private func ipodHTML(_ settings: SettingsManager) -> String {
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead(color: "#c0c0c0"))
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif;-webkit-font-smoothing:antialiased;user-select:none;background:#8a8a8a;display:flex;align-items:center;justify-content:center}
/* iPod body — scales with available space up to 420px wide */
.ipod{
  width:min(88vw,min(calc(80vh * 0.62),420px));
  background:linear-gradient(170deg,#f0f0f0 0%,#d4d4d4 60%,#c8c8c8 100%);
  border-radius:clamp(20px,4vw,32px);
  padding:clamp(12px,2vw,20px);
  box-shadow:0 8px 40px rgba(0,0,0,.55),0 1px 0 rgba(255,255,255,.8) inset,0 0 0 1.5px rgba(0,0,0,.25);
  display:flex;flex-direction:column;gap:clamp(10px,2vw,18px)}
/* Screen */
.screen{
  background:#1a2818;border-radius:clamp(6px,1.2vw,10px);
  padding:clamp(8px,1.5vw,14px) clamp(10px,2vw,16px);
  min-height:clamp(80px,14vw,140px);
  border:2px solid #111;box-shadow:0 2px 8px rgba(0,0,0,.5) inset;overflow:hidden;position:relative}
.screen::before{content:'';position:absolute;top:0;left:0;right:0;height:30%;background:linear-gradient(rgba(255,255,255,.04),transparent);pointer-events:none}
.scr-header{display:flex;justify-content:space-between;align-items:center;border-bottom:1px solid rgba(255,255,255,.07);padding-bottom:5px;margin-bottom:7px}
.scr-label{font-size:clamp(7px,1vw,10px);font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:rgba(255,255,255,.3)}
#scr-status{font-size:clamp(7px,1vw,10px);color:rgba(255,255,255,.3)}
#scr-title{font-size:clamp(12px,1.8vw,17px);font-weight:700;color:#d8f0d0;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;margin-bottom:3px}
#scr-artist{font-size:clamp(10px,1.4vw,13px);color:rgba(180,220,170,.6);overflow:hidden;white-space:nowrap;text-overflow:ellipsis;margin-bottom:clamp(6px,1.5vw,12px)}
.scr-prog-track{height:2px;background:rgba(255,255,255,.1);border-radius:1px;margin-bottom:4px}
.scr-prog-fill{height:100%;background:#7cba5c;border-radius:1px;width:0%;transition:width .5s linear}
.scr-time{display:flex;justify-content:space-between;font-size:clamp(7px,.9vw,9px);color:rgba(180,220,170,.45);font-variant-numeric:tabular-nums}
/* Click wheel — scales proportionally with the body */
.wheel{
  position:relative;
  width:min(72vw,min(calc(64vh * 0.62),330px));
  height:min(72vw,min(calc(64vh * 0.62),330px));
  margin:0 auto;border-radius:50%;
  background:radial-gradient(circle at 38% 32%,#d8d8d8,#b0b0b0);
  box-shadow:0 4px 20px rgba(0,0,0,.38),0 1px 0 rgba(255,255,255,.6) inset}
.wheel-btn{position:absolute;display:flex;align-items:center;justify-content:center;cursor:pointer;-webkit-tap-highlight-color:transparent;color:#555;padding:clamp(8px,1.5vw,16px);transition:color .1s}
.wheel-btn:active{color:#222}
.w-top{top:2px;left:50%;transform:translateX(-50%)}
.w-left{left:2px;top:50%;transform:translateY(-50%)}
.w-right{right:2px;top:50%;transform:translateY(-50%)}
.w-bottom{bottom:2px;left:50%;transform:translateX(-50%)}
.w-top svg,.w-left svg,.w-right svg,.w-bottom svg{width:clamp(16px,2.2vw,26px);height:clamp(16px,2.2vw,26px)}
/* Center button */
.wheel-center{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:42%;height:42%;border-radius:50%;background:radial-gradient(circle at 38% 32%,#e8e8e8,#c0c0c0);box-shadow:0 2px 8px rgba(0,0,0,.28),0 1px 0 rgba(255,255,255,.7) inset;cursor:pointer;-webkit-tap-highlight-color:transparent;display:flex;align-items:center;justify-content:center;transition:background .1s}
.wheel-center:active{background:radial-gradient(circle at 38% 32%,#d8d8d8,#b8b8b8)}
.wheel-center svg{width:clamp(18px,2.8vw,30px);height:clamp(18px,2.8vw,30px);color:#666}
\(connDotCSS.replacingOccurrences(of: "#f44", with: "#c44").replacingOccurrences(of: "#4f4", with: "#484").replacingOccurrences(of: "#fa4", with: "#c80"))
#conn-dot{top:8px;right:8px}
</style></head><body>
<div id="conn-dot" class="connecting"></div>
<div class="ipod">
  <div class="screen">
    <div class="scr-header">
      <span class="scr-label">Now Playing</span>
      <span id="scr-status">▶</span>
    </div>
    <div id="scr-title">—</div>
    <div id="scr-artist"></div>
    <div class="scr-prog-track"><div class="scr-prog-fill" id="scr-fill"></div></div>
    <div class="scr-time"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
  </div>
  <div class="wheel">
    <div class="wheel-btn w-top" onclick="cmd('previousTrack')"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg></div>
    <div class="wheel-btn w-left" onclick="cmd('skipBackward')"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M11 18V6l-8.5 6 8.5 6zm.5-6 8.5 6V6l-8.5 6z"/></svg></div>
    <div class="wheel-btn w-right" onclick="cmd('skipForward')"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M4 18l8.5-6L4 6v12zm9-12v12l8.5-6L13 6z"/></svg></div>
    <div class="wheel-btn w-bottom" onclick="cmd('nextTrack')"><svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg></div>
    <div class="wheel-center" onclick="cmd('togglePlayPause')">
      <svg id="ico-play" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
      <svg id="ico-pause" viewBox="0 0 24 24" fill="currentColor" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
    </div>
  </div>
</div>
<script>
let _dur=0;
window.onStateUpdate=function(s){
  document.getElementById('scr-title').textContent=s.hasMedia?(s.title||'Unknown'):'—';
  document.getElementById('scr-artist').textContent=s.hasMedia?(s.artist||''):'';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('ico-play').style.display=pl?'none':'block';
  document.getElementById('ico-pause').style.display=pl?'block':'none';
  document.getElementById('scr-status').textContent=pl?'▶':'■';
  _dur=(s.durationMicros||0)/1e6;
};
setInterval(()=>{
  const s=getState();if(!s.hasMedia)return;
  const e=elapsed(),d=_dur||0,p=d>0?Math.min(e/d,1):0;
  document.getElementById('scr-fill').style.width=(p*100)+'%';
  const eEl=document.getElementById('pb-e'),rEl=document.getElementById('pb-r');
  if(eEl)eEl.textContent=fmt(e);if(rEl)rEl.textContent='-'+fmt(Math.max(0,d-e));
},500);
\(coreJS)
</script></body></html>
"""
}

// MARK: - Bento ───────────────────────────────────────────────────────────────

private func bentoHTML(_ settings: SettingsManager) -> String {
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead(color: "#111118"))
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif;-webkit-font-smoothing:antialiased;user-select:none;background:#111118;color:#fff}
.root{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;
  padding:max(env(safe-area-inset-top),16px) clamp(16px,3vw,40px) max(env(safe-area-inset-bottom),16px)}
/* Grid — max-width grows with viewport, art row height is unconstrained up to 1:1 ratio */
.grid{
  display:grid;
  width:100%;
  max-width:clamp(340px,80vw,700px);
  grid-template-columns:1fr 1fr;
  grid-template-rows:auto auto auto;
  gap:clamp(8px,1.2vw,14px)}
.card{background:rgba(255,255,255,.06);border-radius:clamp(14px,2vw,22px);border:1px solid rgba(255,255,255,.07);padding:clamp(12px,1.8vw,20px);overflow:hidden}
/* Art card */
.art-card{grid-column:1;grid-row:1;padding:0;aspect-ratio:1;overflow:hidden;border-radius:clamp(14px,2vw,22px)}
#art{width:100%;height:100%;object-fit:cover;display:none;border-radius:inherit}
#art-ph{width:100%;height:100%;display:flex;align-items:center;justify-content:center;font-size:clamp(40px,6vw,80px);background:rgba(255,255,255,.04)}
/* Info card */
.info-card{grid-column:2;grid-row:1;display:flex;flex-direction:column;justify-content:center;gap:4px}
#title{font-size:clamp(14px,2.2vw,24px);font-weight:700;letter-spacing:-.3px;overflow:hidden;display:-webkit-box;-webkit-line-clamp:4;-webkit-box-orient:vertical;line-height:1.25}
#artist{font-size:clamp(11px,1.5vw,16px);color:rgba(255,255,255,.5);overflow:hidden;white-space:nowrap;text-overflow:ellipsis;margin-top:4px}
#album{font-size:clamp(10px,1.2vw,13px);color:rgba(255,255,255,.3);overflow:hidden;white-space:nowrap;text-overflow:ellipsis}
/* Progress card */
.prog-card{grid-column:1 / -1;grid-row:2;padding:clamp(10px,1.5vw,16px) clamp(12px,2vw,20px) clamp(8px,1.2vw,14px)}
\(rangeCSSWhite)
.time-row{display:flex;justify-content:space-between;font-size:clamp(9px,1.1vw,12px);color:rgba(255,255,255,.3);font-variant-numeric:tabular-nums;margin-top:4px}
/* Controls card */
.ctrl-card{grid-column:1 / -1;grid-row:3;display:flex;align-items:center;justify-content:space-around;padding:clamp(10px,1.5vw,16px)}
button{background:none;border:none;cursor:pointer;color:#fff;border-radius:50%;display:flex;align-items:center;justify-content:center;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:transform .12s,opacity .12s,background .12s;padding:0}
button:active{transform:scale(.88);opacity:.6}
.btn-play{width:clamp(52px,6vw,72px);height:clamp(52px,6vw,72px);background:rgba(255,255,255,.14)}
.btn-play:hover{background:rgba(255,255,255,.2)}
.btn-nav{width:clamp(38px,4.5vw,56px);height:clamp(38px,4.5vw,56px);opacity:.8}
\(connDotCSS)
@media(max-height:560px){.art-card{aspect-ratio:unset;height:clamp(100px,30vh,160px)}}
</style></head><body>
<div id="conn-dot" class="connecting"></div>
<div class="root">
  <div class="grid">
    <div class="art-card card"><img id="art" alt=""><div id="art-ph">🎵</div></div>
    <div class="info-card card">
      <div id="title">Nothing Playing</div>
      <div id="artist"></div>
      <div id="album"></div>
    </div>
    <div class="prog-card card">
      <input id="pb" type="range" min="0" max="1000" value="0">
      <div class="time-row"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
    </div>
    <div class="ctrl-card card">
      <button class="btn-nav" onclick="cmd('previousTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg></button>
      <button class="btn-play" onclick="cmd('togglePlayPause')">
        <svg id="ico-play" viewBox="0 0 24 24" fill="currentColor" width="30" height="30"><path d="M8 5v14l11-7z"/></svg>
        <svg id="ico-pause" viewBox="0 0 24 24" fill="currentColor" width="30" height="30" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
      </button>
      <button class="btn-nav" onclick="cmd('nextTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg></button>
    </div>
  </div>
</div>
<script>
let _av=-1;
window.onStateUpdate=function(s){
  document.getElementById('title').textContent=s.hasMedia?(s.title||'Unknown'):'Nothing Playing';
  document.getElementById('artist').textContent=s.hasMedia?(s.artist||''):'';
  document.getElementById('album').textContent=s.hasMedia?(s.album||''):'';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('ico-play').style.display=pl?'none':'block';
  document.getElementById('ico-pause').style.display=pl?'block':'none';
  if(s.hasArtwork&&s.artworkVersion!==_av){
    _av=s.artworkVersion;
    loadArt(img=>{document.getElementById('art').src=img.src;document.getElementById('art').style.display='block';document.getElementById('art-ph').style.display='none'});
  } else if(!s.hasArtwork){_av=-1;document.getElementById('art').style.display='none';document.getElementById('art-ph').style.display='flex'}
};
\(seekBarJS)
\(coreJS)
</script></body></html>
"""
}

// MARK: - Starry Sky ──────────────────────────────────────────────────────────

private func starryHTML(_ settings: SettingsManager) -> String {
    return """
<!DOCTYPE html><html lang="en"><head>
\(pwaHead(color: "#08041a"))
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif;-webkit-font-smoothing:antialiased;user-select:none;background:#08041a;color:#fff}
canvas#stars{position:fixed;inset:0;z-index:0}
/* Aurora curtains — three blobs, shift slowly */
.aur{position:fixed;z-index:1;pointer-events:none;border-radius:50%;filter:blur(70px);mix-blend-mode:screen}
.aur1{width:80vw;height:50vh;top:-15vh;left:-10vw;background:radial-gradient(ellipse,rgba(40,200,160,.45),transparent 70%);animation:_a1 14s ease-in-out infinite alternate}
.aur2{width:70vw;height:45vh;top:-10vh;right:-5vw;background:radial-gradient(ellipse,rgba(100,60,220,.4),transparent 70%);animation:_a2 18s ease-in-out infinite alternate}
.aur3{width:60vw;height:40vh;top:5vh;left:20vw;background:radial-gradient(ellipse,rgba(0,180,220,.3),transparent 70%);animation:_a3 22s ease-in-out infinite alternate}
@keyframes _a1{0%{transform:translateX(0) scaleY(1)}100%{transform:translateX(8vw) scaleY(1.2)}}
@keyframes _a2{0%{transform:translateX(0) scaleY(1)}100%{transform:translateX(-6vw) scaleY(.9)}}
@keyframes _a3{0%{transform:translateX(0) scaleY(1)}100%{transform:translateX(5vw) scaleY(1.15)}}
/* Floating layout — no card */
.root{position:fixed;inset:0;z-index:2;display:flex;flex-direction:column;align-items:center;justify-content:center;
  padding:max(env(safe-area-inset-top),28px) clamp(28px,6vw,80px) max(env(safe-area-inset-bottom),28px);gap:0}
/* Art floats large — drop shadow only, no border/background */
#art-wrap{
  width:clamp(180px,min(46vw,46vh),380px);
  height:clamp(180px,min(46vw,46vh),380px);
  border-radius:clamp(16px,2.5vw,28px);overflow:hidden;flex-shrink:0;
  margin-bottom:clamp(20px,3vh,36px);
  box-shadow:0 24px 80px rgba(20,0,60,.8),0 4px 20px rgba(80,40,180,.4),0 0 0 1px rgba(160,100,255,.12);
  transition:transform .4s cubic-bezier(.4,0,.2,1)}
#art-wrap.playing{transform:scale(1.02)}
#art{width:100%;height:100%;object-fit:cover;display:none}
#art-ph{width:100%;height:100%;background:rgba(80,40,160,.25);display:flex;align-items:center;justify-content:center;font-size:clamp(52px,8vw,100px)}
/* Text floats with subtle glow */
.info{text-align:center;width:100%;max-width:clamp(300px,70vw,680px);margin-bottom:clamp(14px,2.5vh,28px)}
#title{
  font-size:clamp(20px,3.5vw,40px);font-weight:700;letter-spacing:-.4px;line-height:1.15;
  overflow:hidden;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;
  text-shadow:0 0 40px rgba(160,100,255,.5),0 2px 12px rgba(0,0,0,.6)}
#artist{font-size:clamp(13px,1.8vw,20px);color:rgba(180,140,255,.65);margin-top:6px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;letter-spacing:.2px}
/* Progress */
.prog-wrap{width:100%;max-width:clamp(280px,60vw,560px);margin-bottom:clamp(14px,2vh,24px)}
input[type=range]{-webkit-appearance:none;appearance:none;width:100%;height:22px;background:transparent;cursor:pointer;outline:none;--fill:0%}
input[type=range]::-webkit-slider-runnable-track{height:3px;border-radius:2px;background:linear-gradient(to right,rgba(160,100,255,.9) var(--fill),rgba(255,255,255,.12) var(--fill))}
input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:14px;height:14px;border-radius:50%;background:rgba(200,160,255,1);cursor:pointer;margin-top:-5.5px;box-shadow:0 0 10px rgba(160,80,255,.7)}
.time-row{display:flex;justify-content:space-between;font-size:11px;color:rgba(180,140,255,.38);font-variant-numeric:tabular-nums;margin-top:4px}
/* Controls */
.controls{display:flex;align-items:center;gap:clamp(10px,2vw,24px)}
button{background:none;border:none;cursor:pointer;color:#fff;border-radius:50%;display:flex;align-items:center;justify-content:center;-webkit-tap-highlight-color:transparent;touch-action:manipulation;transition:transform .12s,opacity .12s;padding:0}
button:active{transform:scale(.88);opacity:.6}
.btn-play{
  width:clamp(58px,7vw,80px);height:clamp(58px,7vw,80px);
  background:rgba(120,60,220,.3);border:1px solid rgba(160,100,255,.35);
  backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px)}
.btn-nav{width:clamp(40px,5vw,58px);height:clamp(40px,5vw,58px);opacity:.8}
\(connDotCSS)
@media(max-height:560px){
  #art-wrap{width:clamp(110px,38vh,180px);height:clamp(110px,38vh,180px);margin-bottom:12px}
  #title{font-size:clamp(16px,3vh,22px);-webkit-line-clamp:1}
  #artist{display:none}
}
</style></head><body>
<canvas id="stars"></canvas>
<div class="aur aur1"></div><div class="aur aur2"></div><div class="aur aur3"></div>
<div id="conn-dot" class="connecting"></div>
<div class="root">
  <div id="art-wrap"><img id="art" alt=""><div id="art-ph">✦</div></div>
  <div class="info"><div id="title">Nothing Playing</div><div id="artist"></div></div>
  <div class="prog-wrap">
    <input id="pb" type="range" min="0" max="1000" value="0">
    <div class="time-row"><span id="pb-e">0:00</span><span id="pb-r">0:00</span></div>
  </div>
  <div class="controls">
    <button class="btn-nav" onclick="cmd('previousTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z"/></svg></button>
    <button class="btn-play" onclick="cmd('togglePlayPause')">
      <svg id="ico-play" viewBox="0 0 24 24" fill="currentColor" width="30" height="30"><path d="M8 5v14l11-7z"/></svg>
      <svg id="ico-pause" viewBox="0 0 24 24" fill="currentColor" width="30" height="30" style="display:none"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
    </button>
    <button class="btn-nav" onclick="cmd('nextTrack')"><svg viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M6 18l8.5-6L6 6v12zm2-8.14L11.03 12 8 14.14V9.86zM16 6h2v12h-2z"/></svg></button>
  </div>
</div>
<script>
(function(){
  const cvs=document.getElementById('stars'),ctx=cvs.getContext('2d');
  let W,H,stars=[],shoots=[];
  function resize(){
    W=cvs.width=window.innerWidth;H=cvs.height=window.innerHeight;
    stars=[];
    const n=Math.round(W*H/5000);
    for(let i=0;i<n;i++)stars.push({x:Math.random(),y:Math.random(),r:.4+Math.random()*1.3,a:.25+Math.random()*.75,tw:1.5+Math.random()*4,tp:Math.random()*Math.PI*2});
  }
  resize();window.addEventListener('resize',resize);
  function newShoot(){return{x:Math.random()*.75,y:Math.random()*.45,len:100+Math.random()*160,angle:Math.PI/5+Math.random()*.35,speed:7+Math.random()*7,life:1,decay:.015+Math.random()*.01}}
  let nextShoot=1+Math.random()*4;
  function draw(ts){
    ctx.clearRect(0,0,W,H);
    const t=ts/1000;
    ctx.save();
    for(const s of stars){const a=s.a*(.65+.35*Math.sin(t/s.tw+s.tp));ctx.globalAlpha=a;ctx.fillStyle='#fff';ctx.beginPath();ctx.arc(s.x*W,s.y*H,s.r,0,Math.PI*2);ctx.fill()}
    ctx.restore();
    nextShoot-=1/60;
    if(nextShoot<=0){shoots.push(newShoot());nextShoot=2+Math.random()*5}
    for(let i=shoots.length-1;i>=0;i--){
      const sh=shoots[i];
      const x1=sh.x*W,y1=sh.y*H,x2=x1+Math.cos(sh.angle)*sh.len,y2=y1+Math.sin(sh.angle)*sh.len;
      const g=ctx.createLinearGradient(x1,y1,x2,y2);
      g.addColorStop(0,`rgba(200,180,255,${sh.life})`);g.addColorStop(1,'rgba(200,180,255,0)');
      ctx.save();ctx.strokeStyle=g;ctx.lineWidth=1.5;ctx.globalAlpha=sh.life;
      ctx.beginPath();ctx.moveTo(x1,y1);ctx.lineTo(x2,y2);ctx.stroke();ctx.restore();
      sh.x+=Math.cos(sh.angle)*sh.speed/W;sh.y+=Math.sin(sh.angle)*sh.speed/H;sh.life-=sh.decay;
      if(sh.life<=0)shoots.splice(i,1);
    }
    requestAnimationFrame(draw);
  }
  requestAnimationFrame(draw);
})();
let _av=-1;
window.onStateUpdate=function(s){
  document.getElementById('title').textContent=s.hasMedia?(s.title||'Unknown'):'Nothing Playing';
  document.getElementById('artist').textContent=s.hasMedia?(s.artist||''):'';
  const pl=s.isPlaying||(s.playbackRate>0);
  document.getElementById('ico-play').style.display=pl?'none':'block';
  document.getElementById('ico-pause').style.display=pl?'block':'none';
  document.getElementById('art-wrap').classList.toggle('playing',pl&&s.hasMedia);
  if(s.hasArtwork&&s.artworkVersion!==_av){
    _av=s.artworkVersion;
    loadArt(img=>{document.getElementById('art').src=img.src;document.getElementById('art').style.display='block';document.getElementById('art-ph').style.display='none'});
  } else if(!s.hasArtwork){_av=-1;document.getElementById('art').style.display='none';document.getElementById('art-ph').style.display='flex'}
};
\(seekBarJS)
\(coreJS)
</script></body></html>
"""
}
