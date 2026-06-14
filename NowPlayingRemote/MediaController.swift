import Foundation
import AppKit
import MediaRemoteAdapter

final class MediaController {

    private let adapter = MediaRemoteAdapter.MediaController()

    var onUpdate: (() -> Void)?
    private(set) var trackInfo: TrackInfo?
    private(set) var systemVolume: Int = 50
    private(set) var artworkVersion: Int = 0
    private var lastArtworkID: ObjectIdentifier? = nil

    func startListening() {
        adapter.onTrackInfoReceived = { [weak self] info in
            guard let self else { return }
            // Increment artworkVersion whenever the artwork object itself changes,
            // so clients re-fetch even if title/artist stayed the same.
            let newArtwork = info?.payload.artwork
            let newID = newArtwork.map { ObjectIdentifier($0) }
            if newID != self.lastArtworkID {
                self.lastArtworkID = newID
                self.artworkVersion += 1
            }
            self.trackInfo = info
            self.onUpdate?()
        }
        adapter.onListenerTerminated = { [weak self] in
            self?.trackInfo = nil
            self?.onUpdate?()
        }
        adapter.startListening()
        // Fetch initial volume once in the background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.systemVolume = self?.fetchSystemVolume() ?? 50
        }
    }

    private func fetchSystemVolume() -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "output volume of (get volume settings)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.flatMap { Int($0) } ?? systemVolume
    }

    func stopListening() {
        adapter.stopListening()
    }

    // MARK: - Playback controls

    func play()             { adapter.play() }
    func pause()            { adapter.pause() }
    func togglePlayPause()  { adapter.togglePlayPause() }
    func nextTrack()        { adapter.nextTrack() }
    func previousTrack()    { adapter.previousTrack() }
    func stop()             { adapter.stop() }

    func seek(to seconds: Double) { adapter.setTime(seconds: seconds) }

    func skipForward() {
        let secs = Double(SettingsManager.shared.skipInterval)
        if let info = trackInfo?.payload, let elapsed = info.currentElapsedTime {
            let duration = (info.durationMicros ?? 0) / 1_000_000
            adapter.setTime(seconds: min(elapsed + secs, max(duration - 1, 0)))
        } else {
            adapter.skipFifteenSeconds()
        }
    }

    func skipBackward() {
        let secs = Double(SettingsManager.shared.skipInterval)
        if let info = trackInfo?.payload, let elapsed = info.currentElapsedTime {
            adapter.setTime(seconds: max(elapsed - secs, 0))
        } else {
            adapter.goBackFifteenSeconds()
        }
    }

    func toggleShuffle() { adapter.toggleShuffle() }
    func toggleRepeat()  { adapter.toggleRepeat() }

    func setShuffleMode(_ mode: TrackInfo.ShuffleMode) { adapter.setShuffleMode(mode) }
    func setRepeatMode(_ mode: TrackInfo.RepeatMode)   { adapter.setRepeatMode(mode) }

    // MARK: - State snapshot

    func stateJSON() -> [String: Any] {
        guard let info = trackInfo?.payload else {
            return ["hasMedia": false]
        }

        var dict: [String: Any] = [
            "hasMedia": true,
            "isPlaying": info.isPlaying ?? false,
            "playbackRate": info.playbackRate ?? 0.0,
            "hasArtwork": info.artwork != nil,
            "artworkVersion": artworkVersion,
            "volume": systemVolume
        ]

        if let title  = info.title  { dict["title"]  = title }
        if let artist = info.artist { dict["artist"] = artist }
        if let album  = info.album  { dict["album"]  = album }
        if let app    = info.applicationName { dict["applicationName"] = app }

        if let dur = info.durationMicros      { dict["durationMicros"]      = dur }
        if let ela = info.elapsedTimeMicros   { dict["elapsedTimeMicros"]   = ela }
        if let ts  = info.timestampEpochMicros { dict["timestampEpochMicros"] = ts }

        if let shuffle = info.shuffleMode {
            switch shuffle {
            case .off:    dict["shuffleMode"] = "off"
            case .songs:  dict["shuffleMode"] = "songs"
            case .albums: dict["shuffleMode"] = "albums"
            @unknown default: dict["shuffleMode"] = "off"
            }
        }

        if let rep = info.repeatMode {
            switch rep {
            case .off: dict["repeatMode"] = "off"
            case .one: dict["repeatMode"] = "one"
            case .all: dict["repeatMode"] = "all"
            @unknown default: dict["repeatMode"] = "off"
            }
        }

        return dict
    }

    func setSystemVolume(_ percent: Int) {
        systemVolume = max(0, min(100, percent))
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "set volume output volume \(systemVolume)"]
        try? task.run()
    }

    func artworkPNGData() -> Data? {
        guard let img = trackInfo?.payload.artwork else { return nil }
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
