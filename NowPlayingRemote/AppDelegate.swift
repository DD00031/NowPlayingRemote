import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController!
    private var mediaController: MediaController!
    private var httpServer: HTTPServer!
    private var lyricsManager: LyricsManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let settings = SettingsManager.shared
        lyricsManager = LyricsManager()
        mediaController = MediaController()
        httpServer = HTTPServer(mediaController: mediaController,
                                lyricsManager: lyricsManager,
                                settings: settings)
        menuBarController = MenuBarController(
            mediaController: mediaController,
            httpServer: httpServer,
            settings: settings
        )

        lyricsManager.onLyricsReady = { [weak self] in
            self?.httpServer.broadcastStateUpdate()
        }

        mediaController.onUpdate = { [weak self] in
            guard let self else { return }
            if settings.showLyrics, let info = self.mediaController.trackInfo?.payload,
               let title = info.title, let artist = info.artist {
                self.lyricsManager.fetch(title: title, artist: artist,
                                         album: info.album,
                                         durationMicros: info.durationMicros)
            } else if !settings.showLyrics {
                // no-op — don't fetch when disabled
            } else {
                self.lyricsManager.clear()
            }
            self.httpServer.broadcastStateUpdate()
            self.menuBarController.updateMenu()
        }

        mediaController.startListening()

        if settings.autoStartServer {
            try? httpServer.start(port: settings.port)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        httpServer.stop()
        mediaController.stopListening()
    }
}
