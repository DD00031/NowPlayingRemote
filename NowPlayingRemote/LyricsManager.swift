import Foundation

// MARK: - Models

struct LyricsLine: Codable {
    let time: Double   // seconds; -1 = unsynced plain line
    let text: String
}

struct LyricsResult: Codable {
    let source:       String         // "local" | "lrclib"
    let synced:       Bool
    let instrumental: Bool
    let lines:        [LyricsLine]
}

// MARK: - Manager

final class LyricsManager {

    /// Increments every time lyrics change (ready or cleared).
    private(set) var version: Int = 0

    var onLyricsReady: (() -> Void)?

    private var cachedResult: LyricsResult?
    private var fetchingKey: String?

    // MARK: - Public API

    func fetch(title: String, artist: String, album: String?, durationMicros: Double?) {
        let key = "\(title)|\(artist)"
        guard key != fetchingKey else { return }
        fetchingKey = key
        cachedResult = nil
        version += 1          // signal "loading"
        onLyricsReady?()

        let duration = (durationMicros ?? 0) / 1_000_000

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            // 1. Local: embedded lyrics in Music app
            if let local = self.fetchMusicAppLyrics(), !local.isEmpty {
                let parsed = self.parseLRC(local)
                let result: LyricsResult
                if let synced = parsed {
                    result = LyricsResult(source: "local", synced: true, instrumental: false, lines: synced)
                } else {
                    let lines = local.components(separatedBy: .newlines)
                        .map { LyricsLine(time: -1, text: $0.trimmingCharacters(in: .whitespaces)) }
                        .filter { !$0.text.isEmpty }
                    result = LyricsResult(source: "local", synced: false, instrumental: false, lines: lines)
                }
                self.deliverResult(result, forKey: key)
                return
            }

            // 2. Fallback: LRCLIB
            self.fetchLRCLIB(title: title, artist: artist,
                             album: album ?? "", duration: duration) { result in
                if let result { self.deliverResult(result, forKey: key) }
                else          { self.deliverResult(nil,    forKey: key) }
            }
        }
    }

    func clear() {
        fetchingKey = nil
        cachedResult = nil
        version += 1
        onLyricsReady?()
    }

    func currentLyricsJSON() -> [String: Any] {
        guard let r = cachedResult else {
            return ["found": false, "loading": fetchingKey != nil, "version": version]
        }
        let linesArr = r.lines.map { ["time": $0.time, "text": $0.text] }
        return [
            "found":        true,
            "loading":      false,
            "synced":       r.synced,
            "instrumental": r.instrumental,
            "source":       r.source,
            "lines":        linesArr,
            "version":      version
        ]
    }

    // MARK: - Private helpers

    private func deliverResult(_ result: LyricsResult?, forKey key: String) {
        guard fetchingKey == key else { return }
        cachedResult = result
        if result == nil { fetchingKey = nil }  // not found — clear loading flag
        version += 1
        onLyricsReady?()
    }

    // MARK: - Music app (local)

    private func fetchMusicAppLyrics() -> String? {
        let script = """
        tell application "Music"
            try
                if player state is stopped then return ""
                set theLyrics to lyrics of current track
                if theLyrics is missing value then return ""
                return theLyrics
            on error
                return ""
            end try
        end tell
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError  = err
        try? task.run()
        task.waitUntilExit()
        let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw : nil
    }

    // MARK: - LRCLIB

    private func fetchLRCLIB(title: String, artist: String, album: String,
                              duration: Double, completion: @escaping (LyricsResult?) -> Void) {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [
            URLQueryItem(name: "track_name",  value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name",  value: album),
            URLQueryItem(name: "duration",    value: String(Int(duration)))
        ]
        guard let url = comps.url else { completion(nil); return }

        var req = URLRequest(url: url)
        req.setValue("NowPlayingRemote/1.0 (macOS; github.com/ejbills/mediaremote-adapter)",
                     forHTTPHeaderField: "Lrclib-Client")
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil); return
            }

            let instrumental = json["instrumental"] as? Bool ?? false
            if instrumental {
                completion(LyricsResult(source: "lrclib", synced: false,
                                       instrumental: true, lines: []))
                return
            }

            // Synced preferred
            if let raw = json["syncedLyrics"] as? String, !raw.isEmpty,
               let lines = self.parseLRC(raw) {
                completion(LyricsResult(source: "lrclib", synced: true,
                                       instrumental: false, lines: lines))
                return
            }

            // Plain fallback
            if let plain = json["plainLyrics"] as? String, !plain.isEmpty {
                let lines = plain.components(separatedBy: .newlines)
                    .map { LyricsLine(time: -1, text: $0.trimmingCharacters(in: .whitespaces)) }
                    .filter { !$0.text.isEmpty }
                completion(LyricsResult(source: "lrclib", synced: false,
                                       instrumental: false, lines: lines))
                return
            }

            completion(nil)
        }.resume()
    }

    // MARK: - LRC parser  [MM:SS.xx] text

    private func parseLRC(_ lrc: String) -> [LyricsLine]? {
        guard let regex = try? NSRegularExpression(pattern: #"^\[(\d+):(\d+(?:\.\d+)?)\](.*)"#) else { return nil }
        var result: [LyricsLine] = []

        for line in lrc.components(separatedBy: .newlines) {
            let ns = NSRange(line.startIndex..., in: line)
            guard let m = regex.firstMatch(in: line, range: ns), m.numberOfRanges >= 4,
                  let mr = Range(m.range(at: 1), in: line),
                  let sr = Range(m.range(at: 2), in: line),
                  let tr = Range(m.range(at: 3), in: line) else { continue }
            let mins = Double(line[mr]) ?? 0
            let secs = Double(line[sr]) ?? 0
            let text = String(line[tr]).trimmingCharacters(in: .whitespaces)
            result.append(LyricsLine(time: mins * 60 + secs, text: text))
        }
        return result.isEmpty ? nil : result.sorted { $0.time < $1.time }
    }
}
