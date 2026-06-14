import AppKit
import Darwin

final class MenuBarController {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var settingsWindow: NSWindow?
    private var customPlayerWindow: NSWindow?
    private let qrController = QRCodeWindowController()

    private let mediaController: MediaController
    private let httpServer: HTTPServer
    private let settings: SettingsManager

    init(mediaController: MediaController, httpServer: HTTPServer, settings: SettingsManager) {
        self.mediaController = mediaController
        self.httpServer = httpServer
        self.settings = settings
        setupStatusItem()
        buildMenu()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            if let url = Bundle.main.url(forResource: "NowPlayingRemoteIcon", withExtension: "svg"),
               let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = true
                button.image = img
            } else {
                // Fallback to SF Symbol
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Now Playing Remote")
                button.image?.isTemplate = true
            }
        }
    }

    func updateMenu() {
        DispatchQueue.main.async { [weak self] in
            self?.buildMenu()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let trackInfo = mediaController.trackInfo?.payload
        if let title = trackInfo?.title {
            let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)

            if let artist = trackInfo?.artist {
                let artistItem = NSMenuItem(title: artist, action: nil, keyEquivalent: "")
                artistItem.isEnabled = false
                menu.addItem(artistItem)
            }
            menu.addItem(.separator())
        }

        let serverRunning = httpServer.isRunning
        let serverTitle = serverRunning ? "Server: Running on port \(httpServer.currentPort)" : "Server: Stopped"
        let serverItem = NSMenuItem(title: serverTitle, action: nil, keyEquivalent: "")
        serverItem.isEnabled = false
        menu.addItem(serverItem)

        if serverRunning {
            let qrItem = NSMenuItem(title: "Show QR Code", action: #selector(showQRCode), keyEquivalent: "")
            qrItem.target = self
            menu.addItem(qrItem)

            let urlItem = NSMenuItem(title: "Copy Server URL", action: #selector(copyServerURL), keyEquivalent: "")
            urlItem.target = self
            menu.addItem(urlItem)

            let openItem = NSMenuItem(title: "Open in Browser", action: #selector(openInBrowser), keyEquivalent: "")
            openItem.target = self
            menu.addItem(openItem)
        }

        let toggleItem = NSMenuItem(
            title: serverRunning ? "Stop Server" : "Start Server",
            action: #selector(toggleServer),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let customHTML = settings.customPlayerHTML != nil
        let customTitle = customHTML ? "Custom Player… ✓" : "Custom Player…"
        let customItem = NSMenuItem(title: customTitle, action: #selector(openCustomPlayer), keyEquivalent: "")
        customItem.target = self
        menu.addItem(customItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func toggleServer() {
        if httpServer.isRunning {
            httpServer.stop()
        } else {
            try? httpServer.start(port: settings.port)
        }
        buildMenu()
    }

    @objc private func showQRCode() {
        qrController.show(url: localServerURL(), relativeTo: statusItem.button)
    }

    @objc private func copyServerURL() {
        let url = localServerURL()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    @objc private func openInBrowser() {
        if let url = URL(string: localServerURL()) {
            NSWorkspace.shared.open(url)
        }
    }

    private func localServerURL() -> String {
        let ip = getLocalIPAddress() ?? "localhost"
        return "http://\(ip):\(httpServer.currentPort)"
    }

    @objc private func openCustomPlayer() {
        if customPlayerWindow == nil {
            let vc = CustomPlayerViewController(settings: settings)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Now Playing Remote — Custom Player"
            win.contentViewController = vc
            win.minSize = NSSize(width: 560, height: 400)
            win.center()
            win.isReleasedWhenClosed = false
            customPlayerWindow = win
        }
        customPlayerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let vc = SettingsViewController(httpServer: httpServer, settings: settings)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.title = "Now Playing Remote — Settings"
            win.contentViewController = vc
            win.center()
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let addr = current {
            let flags = Int32(addr.pointee.ifa_flags)
            if flags & IFF_LOOPBACK == 0,
               flags & IFF_UP != 0,
               addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
            current = addr.pointee.ifa_next
        }
        return nil
    }
}
