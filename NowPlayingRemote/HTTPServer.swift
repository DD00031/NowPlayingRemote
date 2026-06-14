import Foundation
import Darwin
import AppKit

// MARK: - SSE Client

private final class SSEClient {
    let fd: Int32
    init(fd: Int32) { self.fd = fd }
    deinit { close(fd) }

    func send(_ data: String) {
        let message = "data: \(data)\n\n"
        message.withCString { ptr in
            _ = Darwin.send(fd, ptr, strlen(ptr), 0)
        }
    }

    func sendPing() {
        let ping = ": ping\n\n"
        ping.withCString { ptr in
            _ = Darwin.send(fd, ptr, strlen(ptr), 0)
        }
    }
}

// MARK: - HTTP Server

final class HTTPServer {

    private(set) var isRunning = false
    private(set) var currentPort: Int = 8080

    private var serverFd: Int32 = -1
    private let acceptQueue  = DispatchQueue(label: "com.nowplaying.server.accept")
    private let handleQueue  = DispatchQueue(label: "com.nowplaying.server.handle", attributes: .concurrent)
    private let sseQueue     = DispatchQueue(label: "com.nowplaying.server.sse")
    private var sseClients   = [SSEClient]()
    private var pingTimer: DispatchSourceTimer?

    private weak var mediaController: MediaController?
    private weak var lyricsManager: LyricsManager?
    private let settings: SettingsManager

    init(mediaController: MediaController, lyricsManager: LyricsManager, settings: SettingsManager) {
        self.mediaController = mediaController
        self.lyricsManager   = lyricsManager
        self.settings        = settings
    }

    // MARK: - Lifecycle

    func start(port: Int) throws {
        guard !isRunning else { return }

        serverFd = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw ServerError.socketFailed }

        // Ignore SIGPIPE so broken client connections don't crash the process
        signal(SIGPIPE, SIG_IGN)

        var yes: Int32 = 1
        setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(serverFd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFd)
            throw ServerError.bindFailed(port)
        }

        guard listen(serverFd, 10) == 0 else {
            close(serverFd)
            throw ServerError.listenFailed
        }

        currentPort = port
        isRunning   = true
        startPingTimer()
        acceptLoop()
    }

    func stop() {
        isRunning = false
        pingTimer?.cancel()
        pingTimer = nil
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }
        sseQueue.async { [weak self] in
            self?.sseClients.removeAll()
        }
    }

    // MARK: - Accept loop

    private func acceptLoop() {
        acceptQueue.async { [weak self] in
            guard let self else { return }
            while self.isRunning {
                var clientAddr = sockaddr_in()
                var clientLen  = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFd   = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(self.serverFd, $0, &clientLen)
                    }
                }
                guard clientFd >= 0 else { continue }

                var nosig: Int32 = 1
                setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))

                // Set read timeout so stuck connections don't hold threads
                var tv = timeval(tv_sec: 5, tv_usec: 0)
                setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                self.handleQueue.async {
                    self.handleConnection(clientFd)
                }
            }
        }
    }

    // MARK: - Request handling

    private func handleConnection(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let n = recv(fd, &buffer, buffer.count - 1, 0)
        guard n > 0 else { close(fd); return }

        let raw   = String(bytes: buffer.prefix(n), encoding: .utf8) ?? ""
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { close(fd); return }

        let parts  = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { close(fd); return }

        let method = parts[0]
        let fullPath = parts[1]
        let path   = fullPath.components(separatedBy: "?").first ?? fullPath

        var body = ""
        if let range = raw.range(of: "\r\n\r\n") {
            body = String(raw[range.upperBound...])
        }

        switch (method, path) {
        case ("GET",  "/"):              servePlayer(fd)
        case ("GET",  "/api/state"):     serveState(fd)
        case ("GET",  "/api/artwork"):   serveArtwork(fd)
        case ("GET",  "/api/lyrics"):    serveLyrics(fd)
        case ("GET",  "/events"):        registerSSEClient(fd); return
        case ("POST", "/api/command"):   handleCommand(fd, body: body)
        case ("GET",  "/manifest.json"): serveManifest(fd)
        case ("GET",  "/icon-180.png"):  serveAppIcon(fd)
        case ("OPTIONS", _):             sendCORSPreflight(fd)
        default:                         send404(fd)
        }

        close(fd)
    }

    // MARK: - Route handlers

    private func servePlayer(_ fd: Int32) {
        let html = playerHTML(settings: settings)
        let response = httpResponse(status: "200 OK",
                                    contentType: "text/html; charset=utf-8",
                                    body: html.data(using: .utf8) ?? Data())
        sendAll(fd, data: response)
    }

    private func serveState(_ fd: Int32) {
        let dict = mediaController?.stateJSON() ?? ["hasMedia": false]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            send500(fd); return
        }
        let response = httpResponse(status: "200 OK",
                                    contentType: "application/json",
                                    body: data,
                                    extraHeaders: corsHeaders())
        sendAll(fd, data: response)
    }

    private func serveArtwork(_ fd: Int32) {
        guard let data = mediaController?.artworkPNGData() else {
            send404(fd); return
        }
        let response = httpResponse(status: "200 OK",
                                    contentType: "image/png",
                                    body: data,
                                    extraHeaders: "Cache-Control: no-store\r\n" + corsHeaders())
        sendAll(fd, data: response)
    }

    private func serveLyrics(_ fd: Int32) {
        let dict = lyricsManager?.currentLyricsJSON() ?? ["found": false, "loading": false, "version": 0]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { send500(fd); return }
        let response = httpResponse(status: "200 OK",
                                    contentType: "application/json",
                                    body: data,
                                    extraHeaders: "Cache-Control: no-store\r\n" + corsHeaders())
        sendAll(fd, data: response)
    }

    private func serveManifest(_ fd: Int32) {
        let manifest = """
        {
          "name": "Now Playing Remote",
          "short_name": "Now Playing",
          "start_url": "/",
          "display": "standalone",
          "background_color": "#0a0a14",
          "theme_color": "#0a0a14",
          "orientation": "portrait-primary",
          "icons": [{"src": "/icon-180.png", "sizes": "180x180", "type": "image/png", "purpose": "any"}]
        }
        """
        let response = httpResponse(status: "200 OK",
                                    contentType: "application/manifest+json",
                                    body: Data(manifest.utf8))
        sendAll(fd, data: response)
    }

    private lazy var cachedHomescreenIconPNG: Data? = {
        let size: CGFloat = 180
        guard let url = Bundle.main.url(forResource: "HomescreenIcon", withExtension: "png"),
              let source = NSImage(contentsOf: url) else { return nil }
        let resized = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
        guard let tiff = resized.tiffRepresentation,
              let rep  = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }()

    private func serveAppIcon(_ fd: Int32) {
        guard let data = cachedHomescreenIconPNG else { send500(fd); return }
        let response = httpResponse(status: "200 OK",
                                    contentType: "image/png",
                                    body: data,
                                    extraHeaders: "Cache-Control: max-age=86400\r\n")
        sendAll(fd, data: response)
    }

    private func handleCommand(_ fd: Int32, body: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = json["command"] as? String else {
            send400(fd); return
        }

        switch command {
        case "play":              mediaController?.play()
        case "pause":             mediaController?.pause()
        case "togglePlayPause":   mediaController?.togglePlayPause()
        case "nextTrack":         mediaController?.nextTrack()
        case "previousTrack":     mediaController?.previousTrack()
        case "stop":              mediaController?.stop()
        case "skipForward":       mediaController?.skipForward()
        case "skipBackward":      mediaController?.skipBackward()
        case "toggleShuffle":     mediaController?.toggleShuffle()
        case "toggleRepeat":      mediaController?.toggleRepeat()
        case "setVolume":
            if let v = json["value"] as? Double {
                mediaController?.setSystemVolume(Int(v))
            }
        case "seek":
            if let secs = json["value"] as? Double {
                mediaController?.seek(to: secs)
            }
        case "setShuffleMode":
            if let val = json["value"] as? String {
                switch val {
                case "off":    mediaController?.setShuffleMode(.off)
                case "songs":  mediaController?.setShuffleMode(.songs)
                case "albums": mediaController?.setShuffleMode(.albums)
                default: break
                }
            }
        case "setRepeatMode":
            if let val = json["value"] as? String {
                switch val {
                case "off": mediaController?.setRepeatMode(.off)
                case "one": mediaController?.setRepeatMode(.one)
                case "all": mediaController?.setRepeatMode(.all)
                default: break
                }
            }
        default: break
        }

        let ok = "{\"ok\":true}".data(using: .utf8)!
        let response = httpResponse(status: "200 OK",
                                    contentType: "application/json",
                                    body: ok,
                                    extraHeaders: corsHeaders())
        sendAll(fd, data: response)
    }

    // MARK: - SSE

    private func registerSSEClient(_ fd: Int32) {
        let headers = "HTTP/1.1 200 OK\r\n" +
                      "Content-Type: text/event-stream\r\n" +
                      "Cache-Control: no-cache\r\n" +
                      "Connection: keep-alive\r\n" +
                      corsHeaders() +
                      "\r\n"
        guard sendAll(fd, data: Data(headers.utf8)) else { close(fd); return }

        // Remove read timeout so the connection stays open
        var tv = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let client = SSEClient(fd: fd)

        // Send current state immediately
        var initDict = mediaController?.stateJSON() ?? ["hasMedia": false]
        initDict["lyricsVersion"] = lyricsManager?.version ?? 0
        if let data = try? JSONSerialization.data(withJSONObject: initDict),
           let str  = String(data: data, encoding: .utf8) {
            client.send(str)
        }

        sseQueue.async { [weak self] in
            self?.sseClients.append(client)
        }
    }

    func broadcastStateUpdate() {
        var dict = mediaController?.stateJSON() ?? ["hasMedia": false]
        dict["lyricsVersion"] = lyricsManager?.version ?? 0
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str  = String(data: data, encoding: .utf8) else { return }

        sseQueue.async { [weak self] in
            guard let self else { return }
            var dead = [Int]()
            for (i, client) in self.sseClients.enumerated() {
                client.send(str)
                // Check if connection is still alive with a simple poll
                var pfd = pollfd(fd: client.fd, events: Int16(POLLHUP | POLLERR), revents: 0)
                if poll(&pfd, 1, 0) > 0 && (pfd.revents & Int16(POLLHUP | POLLERR)) != 0 {
                    dead.append(i)
                }
            }
            for i in dead.reversed() { self.sseClients.remove(at: i) }
        }
    }

    private func startPingTimer() {
        let timer = DispatchSource.makeTimerSource(queue: sseQueue)
        timer.schedule(deadline: .now() + 25, repeating: 25)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var dead = [Int]()
            for (i, client) in self.sseClients.enumerated() {
                client.sendPing()
                var pfd = pollfd(fd: client.fd, events: Int16(POLLHUP | POLLERR), revents: 0)
                if poll(&pfd, 1, 0) > 0 && (pfd.revents & Int16(POLLHUP | POLLERR)) != 0 {
                    dead.append(i)
                }
            }
            for i in dead.reversed() { self.sseClients.remove(at: i) }
        }
        timer.resume()
        pingTimer = timer
    }

    // MARK: - Helpers

    @discardableResult
    private func sendAll(_ fd: Int32, data: Data) -> Bool {
        var sent = 0
        while sent < data.count {
            let n = data.withUnsafeBytes { ptr in
                Darwin.send(fd, ptr.baseAddress!.advanced(by: sent), data.count - sent, MSG_NOSIGNAL)
            }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }

    private func httpResponse(status: String, contentType: String, body: Data,
                              extraHeaders: String = "") -> Data {
        let header = "HTTP/1.1 \(status)\r\n" +
                     "Content-Type: \(contentType)\r\n" +
                     "Content-Length: \(body.count)\r\n" +
                     "Connection: close\r\n" +
                     extraHeaders +
                     "\r\n"
        var result = Data(header.utf8)
        result.append(body)
        return result
    }

    private func corsHeaders() -> String {
        "Access-Control-Allow-Origin: *\r\n" +
        "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n" +
        "Access-Control-Allow-Headers: Content-Type\r\n"
    }

    private func sendCORSPreflight(_ fd: Int32) {
        let response = "HTTP/1.1 204 No Content\r\n" + corsHeaders() + "\r\n"
        sendAll(fd, data: Data(response.utf8))
    }

    private func send400(_ fd: Int32) {
        let body = Data("Bad Request".utf8)
        sendAll(fd, data: httpResponse(status: "400 Bad Request", contentType: "text/plain", body: body))
    }

    private func send404(_ fd: Int32) {
        let body = Data("Not Found".utf8)
        sendAll(fd, data: httpResponse(status: "404 Not Found", contentType: "text/plain", body: body))
    }

    private func send500(_ fd: Int32) {
        let body = Data("Internal Server Error".utf8)
        sendAll(fd, data: httpResponse(status: "500 Internal Server Error", contentType: "text/plain", body: body))
    }
}

// MARK: - Error

enum ServerError: Error, LocalizedError {
    case socketFailed
    case bindFailed(Int)
    case listenFailed

    var errorDescription: String? {
        switch self {
        case .socketFailed:       return "Failed to create socket"
        case .bindFailed(let p):  return "Failed to bind to port \(p) — is it already in use?"
        case .listenFailed:       return "Failed to start listening"
        }
    }
}

// MARK: - HTML Player

private func playerHTML(settings: SettingsManager) -> String {
    let skipSecs   = settings.skipInterval
    let showVol    = settings.showVolumeControl
    let showLyrics = settings.showLyrics
    return """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Now Playing">
<meta name="theme-color" content="#0a0a14">
<link rel="manifest" href="/manifest.json">
<link rel="apple-touch-icon" href="/icon-180.png">
<title>Now Playing</title>
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
    position: fixed;
    top: 0px; left: 0px; 
    width: 100vw;
    height: 100vh;
    background: linear-gradient(160deg, var(--c1) 0%, var(--c2) 100%);
    transition: background var(--transition);
    z-index: 0;
  }
  #bg::after {
    content: ''; position: absolute; inset: 0;
    background: rgba(0,0,0,0.32);
  }
  #blur-art {
    position: absolute; inset: -40px;
    background-size: cover; background-position: center;
    filter: blur(60px) saturate(1.8);
    opacity: 0; transition: opacity 0.8s ease;
    transform: scale(1.15);
  }
  #blur-art.visible { opacity: 1; }

  /* ── App wrapper ─────────────────────────────────── */
  .app-wrap {
    position: fixed; inset: 0; z-index: 1;
    display: flex; align-items: stretch;
  }

  /* ── Player panel ────────────────────────────────── */
  .player-panel {
    flex: 1 0 0;
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    padding: max(env(safe-area-inset-top),20px) 24px max(env(safe-area-inset-bottom),24px);
    max-width: 480px; width: 100%; margin: 0 auto;
    min-height: 0;
  }

  /* Artwork */
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

  /* Track info */
  .track-info { width:100%; text-align:center; margin-bottom:18px; min-height:55px; }
  #title { font-size:clamp(17px,5vw,21px); font-weight:700; color:var(--text); letter-spacing:-0.3px; line-height:1.2; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin-bottom:5px; }
  #artist { font-size:clamp(13px,4vw,15px); color:var(--text-sub); font-weight:500; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  #album { font-size:11px; color:var(--text-sub); opacity:0.65; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; margin-top:2px; }

  /* Progress */
  .progress-wrap { width:100%; margin-bottom:14px; }
  #progress-bar {
    -webkit-appearance:none; appearance:none;
    width:100%; height:22px; background:transparent; cursor:pointer; outline:none; --fill:0%;
  }
  #progress-bar::-webkit-slider-runnable-track {
    height:4px; border-radius:2px;
    background: linear-gradient(to right, rgba(255,255,255,0.88) var(--fill), rgba(255,255,255,0.2) var(--fill));
  }
  #progress-bar::-webkit-slider-thumb {
    -webkit-appearance:none; width:18px; height:18px; border-radius:50%;
    background:#fff; cursor:pointer; margin-top:-7px;
    box-shadow:0 2px 8px rgba(0,0,0,0.45); transition:transform 0.1s;
  }
  #progress-bar:active::-webkit-slider-thumb { transform:scale(1.25); }
  .time-row { display:flex; justify-content:space-between; font-size:11px; color:var(--text-sub); font-variant-numeric:tabular-nums; font-weight:500; }

  /* Controls */
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

  /* Volume */
  .volume-row { display:flex;align-items:center;gap:8px;width:100%;padding:0 4px;color:var(--text);opacity:0.8; }
  .btn-vol { width:34px;height:34px;border-radius:50%;flex-shrink:0;color:var(--text);opacity:0.85; }
  .btn-vol:hover { background:rgba(255,255,255,0.12);opacity:1; }
  .btn-vol:active { transform:scale(0.88); }
  .btn-vol svg { width:20px;height:20px;fill:currentColor;pointer-events:none; }
  #volume-slider { flex:1;-webkit-appearance:none;appearance:none;height:22px;background:transparent;outline:none;--vol-fill:50%; }
  #volume-slider::-webkit-slider-runnable-track { height:3px;border-radius:2px;background:linear-gradient(to right,rgba(255,255,255,0.85) var(--vol-fill),rgba(255,255,255,0.2) var(--vol-fill)); }
  #volume-slider::-webkit-slider-thumb { -webkit-appearance:none;width:16px;height:16px;border-radius:50%;background:#fff;cursor:pointer;margin-top:-6.5px;box-shadow:0 2px 6px rgba(0,0,0,0.4); }

  /* Lyrics open button (mobile only, shown when lyrics enabled) */
  .btn-lyrics-open {
    margin-top: 14px;
    padding: 7px 22px;
    border: 1px solid rgba(255,255,255,0.22);
    border-radius: 20px;
    color: rgba(255,255,255,0.72);
    font-size: 13px; font-weight: 600;
    background: rgba(255,255,255,0.07);
    letter-spacing: 0.2px;
    transition: background 0.15s ease, opacity 0.15s ease;
  }
  .btn-lyrics-open:active { background: rgba(255,255,255,0.14); }

  /* ── Lyrics panel ────────────────────────────────── */
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
    border-bottom: 1px solid rgba(255,255,255,0.08);
    flex-shrink: 0;
  }
  .lyrics-panel-header h2 { flex:1;font-size:16px;font-weight:700;color:var(--text); }
  .lyrics-source-badge {
    font-size:10px;font-weight:600;letter-spacing:0.6px;text-transform:uppercase;
    color:rgba(255,255,255,0.4); padding:3px 8px;
    border:1px solid rgba(255,255,255,0.15);border-radius:10px;margin-right:10px;
  }
  .btn-close-lyrics {
    width:30px;height:30px;border-radius:50%;
    color:rgba(255,255,255,0.6);font-size:18px;
    background:rgba(255,255,255,0.08);
  }
  .btn-close-lyrics:hover { background:rgba(255,255,255,0.16); }

  .lyrics-scroll {
    flex:1; overflow-y:auto;
    padding: 12px 8px max(env(safe-area-inset-bottom), 32px);
    scrollbar-width:none;
  }
  .lyrics-scroll::-webkit-scrollbar { display:none; }

  .lyric-line {
    padding: 9px 20px;
    font-size: 16px; font-weight: 500;
    color: rgba(255,255,255,0.3);
    line-height: 1.55; text-align: center;
    border-radius: 10px;
    transition: color 0.25s ease, font-size 0.25s ease, font-weight 0.25s ease;
    cursor: pointer;
  }
  .lyric-line:empty::after { content:'♪'; }
  .lyric-line.active {
    color: rgba(255,255,255,0.95);
    font-size: 19px; font-weight: 700;
  }
  .lyric-line.near-active { color: rgba(255,255,255,0.55); }
  .lyric-line:not(.active):hover { color:rgba(255,255,255,0.55); background:rgba(255,255,255,0.05); }

  .lyrics-status {
    text-align:center; padding:48px 24px;
    color:rgba(255,255,255,0.35); font-size:15px; font-weight:500;
  }

  /* ── Desktop ────────────────────────────────────────── */
  @media (min-width: 700px) {
    .app-wrap { justify-content: center; align-items: center; }
    .btn-lyrics-open { display: none; }
  }

\(showLyrics ? """
  /* Desktop: two-column with cards (lyrics on) */
  @media (min-width: 700px) {
    .app-wrap { padding: 32px; gap: 20px; }
    .player-panel {
      flex: 0 0 300px; max-width: 300px; margin: 0;
      padding: 28px 24px;
      max-height: min(700px, calc(100vh - 64px));
      border-radius: 24px;
      background: rgba(255,255,255,0.05);
      backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255,255,255,0.08);
      overflow: hidden;
    }
    #artwork-wrap { width: min(44vw, 44vh, 220px); height: min(44vw, 44vh, 220px); }
    .lyrics-panel {
      position: static; transform: none;
      flex: 1; max-width: 440px;
      max-height: min(700px, calc(100vh - 64px));
      border-radius: 24px;
      background: rgba(255,255,255,0.04);
      backdrop-filter: blur(20px); -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255,255,255,0.08);
    }
    .lyrics-panel-header { padding: 20px 20px 14px; }
    .lyrics-scroll { padding-bottom: 28px; }
    .btn-close-lyrics { display: none; }
  }
""" : "")

  /* ── Misc ───────────────────────────────────────── */
  #conn-dot {
    position:fixed; top:max(env(safe-area-inset-top,0px),12px); right:14px;
    width:8px;height:8px;border-radius:50%;background:#ff4444;
    transition:background 0.3s; z-index:100;
  }
  #conn-dot.connected { background:#44ff88; }
  #conn-dot.connecting { background:#ffaa00; animation:pulse 1s infinite; }
  @keyframes pulse { 0%,100%{opacity:1}50%{opacity:0.3} }

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

  <!-- ── Player ── -->
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
      <input id="progress-bar" type="range" min="0" max="1000" value="0" step="1">
      <div class="time-row">
        <span id="time-elapsed">0:00</span>
        <span id="time-remaining">0:00</span>
      </div>
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

    \(showLyrics ? """
    <button class="btn-lyrics-open" onclick="toggleLyricsPanel()" id="btn-lyrics-open">Lyrics</button>
    """ : "")
  </div>

  <!-- ── Lyrics panel ── -->
  \(showLyrics ? """
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

  // ── State ──────────────────────────────────────────────────────────────────
  let state            = { hasMedia: false };
  let lastArtworkVer   = -1;
  let lastLyricsVer    = -1;
  let lyricData        = [];
  let lyricsRetryTimer = null;
  let progressInterval = null;
  let isDragging       = false;
  let evtSource        = null;
  let reconnectDelay   = 1000;

  const $ = id => document.getElementById(id);

  // ── SSE ────────────────────────────────────────────────────────────────────
  function connect() {
    if (evtSource) evtSource.close();
    $('conn-dot').className = 'connecting';
    evtSource = new EventSource('/events');
    evtSource.onopen    = () => { $('conn-dot').className = 'connected'; reconnectDelay = 1000; };
    evtSource.onmessage = e  => { try { applyState(JSON.parse(e.data)); } catch(_) {} };
    evtSource.onerror   = () => {
      $('conn-dot').className = '';
      evtSource.close(); evtSource = null;
      setTimeout(connect, reconnectDelay);
      reconnectDelay = Math.min(reconnectDelay * 1.5, 15000);
    };
  }

  // ── Apply state ────────────────────────────────────────────────────────────
  function applyState(s) {
    state = s;
    const playEl  = $('icon-play');
    const pauseEl = $('icon-pause');

    if (!s.hasMedia) {
      $('title').textContent  = 'Nothing Playing';
      $('artist').textContent = '';
      $('album').textContent  = '';
      if (playEl)  playEl.style.display  = 'block';
      if (pauseEl) pauseEl.style.display = 'none';
      $('artwork-wrap').classList.remove('playing');
      lastArtworkVer = -1; clearArtwork();
      stopProgress(); setProgress(0,0);
      renderLyricsStatus('Play something to load lyrics');
      return;
    }

    $('title').textContent  = s.title  || 'Unknown Title';
    $('artist').textContent = s.artist || '';
    $('album').textContent  = s.album  || '';

    const playing = s.isPlaying || (s.playbackRate && s.playbackRate > 0);
    if (playEl)  playEl.style.display  = playing ? 'none'  : 'block';
    if (pauseEl) pauseEl.style.display = playing ? 'block' : 'none';
    $('artwork-wrap').classList.toggle('playing', playing);

    const artVer = s.artworkVersion ?? -1;
    if (s.hasArtwork && artVer !== lastArtworkVer) { lastArtworkVer = artVer; loadArtwork(); }
    else if (!s.hasArtwork) { lastArtworkVer = -1; clearArtwork(); }

    if (s.volume != null) {
      const vs = $('volume-slider');
      if (vs) { vs.value = s.volume; updateVolumeFill(); }
    }

    if (s.lyricsVersion !== undefined && s.lyricsVersion !== lastLyricsVer) {
      lastLyricsVer = s.lyricsVersion;
      fetchLyrics();
    }

    startProgress();
  }

  // ── Artwork ────────────────────────────────────────────────────────────────
  function loadArtwork() {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      $('artwork').src = img.src;
      $('artwork').style.display = 'block';
      $('artwork-placeholder').style.display = 'none';
      $('blur-art').style.backgroundImage = `url('${img.src}')`;
      $('blur-art').classList.add('visible');
      extractColors(img);
    };
    img.src = '/api/artwork?' + Date.now();
  }
  function clearArtwork() {
    $('artwork').style.display = 'none';
    $('artwork').src = '';
    $('artwork-placeholder').style.display = 'flex';
    $('blur-art').classList.remove('visible');
    setGradient('#1a1a2e','#16213e');
  }
  function extractColors(img) {
    try {
      const c = document.createElement('canvas'); c.width = c.height = 80;
      const ctx = c.getContext('2d'); ctx.drawImage(img,0,0,80,80);
      const d = ctx.getImageData(0,0,80,80).data;
      let r=0,g=0,b=0,n=0;
      for (let i=0;i<d.length;i+=64) { r+=d[i];g+=d[i+1];b+=d[i+2];n++; }
      r=Math.round(r/n);g=Math.round(g/n);b=Math.round(b/n);
      const lum = 0.299*r+0.587*g+0.114*b;
      if (lum>180) { r=Math.round(r*.5);g=Math.round(g*.5);b=Math.round(b*.5); }
      setGradient(`rgb(${r},${g},${b})`,`rgb(${Math.round(r*.5)},${Math.round(g*.5)},${Math.round(b*.5)})`);
      document.documentElement.style.setProperty('--accent-tint',`rgb(${Math.min(255,r+80)},${Math.min(255,g+80)},${Math.min(255,b+80)})`);
    } catch(_) {}
  }
  function setGradient(c1,c2) {
    document.documentElement.style.setProperty('--c1',c1);
    document.documentElement.style.setProperty('--c2',c2);
  }

  // ── Progress ────────────────────────────────────────────────────────────────
  function currentElapsed() {
    if (state.timestampEpochMicros == null) return 0;
    const rate  = state.playbackRate ?? 0;
    const base  = (state.elapsedTimeMicros ?? 0) / 1e6;
    const stamp = state.timestampEpochMicros / 1e6;
    return Math.max(0, base + (Date.now()/1000 - stamp) * rate);
  }
  function updateProgressFill() {
    const pct = (($('progress-bar').value / 1000) * 100);
    $('progress-bar').style.setProperty('--fill', pct + '%');
  }
  function setProgress(elapsed, duration) {
    const pct = duration > 0 ? Math.min(elapsed/duration,1) : 0;
    if (!isDragging) { $('progress-bar').value = Math.round(pct*1000); updateProgressFill(); }
    $('time-elapsed').textContent   = formatTime(elapsed);
    $('time-remaining').textContent = '-' + formatTime(Math.max(0,duration-elapsed));
  }
  function startProgress() {
    stopProgress();
    function tick() {
      if (!state.hasMedia) return;
      const elapsed = currentElapsed();
      const dur = (state.durationMicros||0)/1e6;
      setProgress(elapsed, dur);
      updateLyricsHighlight(elapsed);
    }
    tick();
    progressInterval = setInterval(tick, 500);
  }
  function stopProgress() { if (progressInterval) { clearInterval(progressInterval); progressInterval=null; } }

  const pb = $('progress-bar');
  if (pb) {
    pb.addEventListener('mousedown',  () => { isDragging=true; });
    pb.addEventListener('touchstart', () => { isDragging=true; }, {passive:true});
    pb.addEventListener('input', () => {
      updateProgressFill();
      if (!state.durationMicros) return;
      const secs = (pb.value/1000)*(state.durationMicros/1e6);
      $('time-elapsed').textContent   = formatTime(secs);
      $('time-remaining').textContent = '-'+formatTime(Math.max(0,state.durationMicros/1e6-secs));
    });
    pb.addEventListener('change', () => {
      isDragging=false;
      if (!state.durationMicros) return;
      cmd('seek', (pb.value/1000)*(state.durationMicros/1e6));
    });
  }

  // ── Lyrics ─────────────────────────────────────────────────────────────────
  function fetchLyrics() {
    if (lyricsRetryTimer) { clearTimeout(lyricsRetryTimer); lyricsRetryTimer = null; }
    const panel = $('lyrics-lines');
    if (!panel) return;
    fetch('/api/lyrics')
      .then(r => r.json())
      .then(data => {
        renderLyrics(data);
        // Server-side fetch still in progress — poll again after 25s as fallback
        if (data.loading) {
          lyricsRetryTimer = setTimeout(fetchLyrics, 25000);
        }
      })
      .catch(() => renderLyricsStatus('Could not load lyrics'));
  }

  function renderLyrics(data) {
    const container = $('lyrics-lines');
    const badge     = $('lyrics-source');
    if (!container) return;

    if (data.loading) { renderLyricsStatus('Loading lyrics…'); lyricData=[]; return; }
    // Done (found or not) — cancel any pending retry
    if (lyricsRetryTimer) { clearTimeout(lyricsRetryTimer); lyricsRetryTimer = null; }
    if (!data.found)  { renderLyricsStatus('No lyrics found'); lyricData=[]; if(badge)badge.textContent=''; return; }
    if (data.instrumental) { renderLyricsStatus('♪ Instrumental'); lyricData=[]; if(badge)badge.textContent=''; return; }

    lyricData = (data.lines || []).filter(l => l.text && l.text.trim());
    if (badge) badge.textContent = data.source === 'local' ? 'Music app' : 'LRCLib';

    container.innerHTML = lyricData.map((l,i) =>
      `<div class="lyric-line" id="ly${i}" data-t="${l.time}" onclick="seekToLyric(${l.time})">${escHtml(l.text)}</div>`
    ).join('');
  }

  function renderLyricsStatus(msg) {
    lyricData = [];
    const el = $('lyrics-lines');
    if (el) el.innerHTML = `<div class="lyrics-status">${msg}</div>`;
  }

  function updateLyricsHighlight(elapsed) {
    if (!lyricData.length) return;
    let active = -1;
    for (let i=0;i<lyricData.length;i++) {
      if (lyricData[i].time < 0 || lyricData[i].time <= elapsed) active=i;
      else break;
    }
    const lines = document.querySelectorAll('.lyric-line');
    lines.forEach((el,i) => {
      const wasActive = el.classList.contains('active');
      el.classList.toggle('active', i===active);
      el.classList.toggle('near-active', Math.abs(i-active)<=1 && i!==active);
      if (!wasActive && i===active && i>=0) {
        el.scrollIntoView({behavior:'smooth', block:'center'});
      }
    });
  }

  window.seekToLyric = t => { if (t >= 0) cmd('seek', t); };

  window.toggleLyricsPanel = () => {
    $('lyrics-panel')?.classList.toggle('open');
  };

  // ── Volume ──────────────────────────────────────────────────────────────────
  const volSlider = $('volume-slider');
  function updateVolumeFill() {
    if (!volSlider) return;
    volSlider.style.setProperty('--vol-fill', volSlider.value + '%');
  }
  window.stepVolume = delta => {
    if (!volSlider) return;
    const next = Math.max(0, Math.min(100, parseInt(volSlider.value,10)+delta));
    volSlider.value = next; updateVolumeFill(); cmd('setVolume', next);
  };
  if (volSlider) {
    volSlider.addEventListener('input',  updateVolumeFill);
    volSlider.addEventListener('change', () => cmd('setVolume', parseInt(volSlider.value,10)));
    updateVolumeFill();
  }

  // ── Commands ────────────────────────────────────────────────────────────────
  window.cmd = (command, value) => {
    const body = {command};
    if (value !== undefined) body.value = value;
    fetch('/api/command', {
      method:'POST', headers:{'Content-Type':'application/json'},
      body:JSON.stringify(body)
    }).catch(()=>{});
  };

  // ── Helpers ─────────────────────────────────────────────────────────────────
  function formatTime(secs) {
    const s=Math.floor(secs), m=Math.floor(s/60), h=Math.floor(m/60);
    return h>0 ? `${h}:${pad(m%60)}:${pad(s%60)}` : `${m}:${pad(s%60)}`;
  }
  function pad(n) { return String(n).padStart(2,'0'); }
  function escHtml(t) { return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

  // ── Init ────────────────────────────────────────────────────────────────────
  connect();
})();
</script>
</body>
</html>
"""
}
