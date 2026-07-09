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
        case ("GET", _) where path.hasPrefix("/theme-assets/"): serveThemeAsset(fd, path: path)
        default:                         send404(fd)
        }

        close(fd)
    }

    // MARK: - Route handlers

    private func servePlayer(_ fd: Int32) {
        let html: String
        let tm = ThemeArchiveManager.shared
        if let customHTML = settings.customPlayerHTML {
            html = customHTML
        } else if let customJS = settings.customPlayerJS {
            html = jsShellHTML(js: customJS)
        } else if settings.useThemeArchive && tm.isInstalled {
            html = customThemeArchiveHTML(themeManager: tm, settings: settings)
        } else {
            html = themeHTML(for: settings.selectedTheme, settings: settings)
        }
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

    private func serveThemeAsset(_ fd: Int32, path: String) {
        let filename = String(path.dropFirst("/theme-assets/".count))
        guard !filename.isEmpty else { send404(fd); return }
        let tm = ThemeArchiveManager.shared
        guard let data = tm.assetData(name: filename) else { send404(fd); return }
        let response = httpResponse(status: "200 OK",
                                    contentType: tm.mimeType(for: filename),
                                    body: data)
        sendAll(fd, data: response)
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

