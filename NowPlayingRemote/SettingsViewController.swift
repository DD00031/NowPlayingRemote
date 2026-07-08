import AppKit
import Darwin
import UniformTypeIdentifiers

final class SettingsViewController: NSViewController {

    private let httpServer: HTTPServer
    private let settings: SettingsManager

    // UI
    private var portField        = NSTextField()
    private var portStepper      = NSStepper()
    private var autoStartCheck   = NSButton()
    private var launchLoginCheck = NSButton()
    private var skipPopup        = NSPopUpButton()
    private var volumeCheck      = NSButton()
    private var likeCheck        = NSButton()
    private var lyricsCheck      = NSButton()
    private var serverToggleBtn  = NSButton()
    private var statusLabel      = NSTextField()
    private var urlLabel         = NSTextField()
    private var applyPortBtn     = NSButton()
    private var themePopup        = NSPopUpButton()
    private var customFileLabel  = NSTextField()
    private var resetCustomBtn   = NSButton()

    init(httpServer: HTTPServer, settings: SettingsManager) {
        self.httpServer = httpServer
        self.settings   = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 700))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refresh()
    }

    // MARK: - UI Construction

    private func buildUI() {
        var y: CGFloat = 650

        func addLabel(_ text: String, x: CGFloat, width: CGFloat, yOff: CGFloat = 0) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.frame = NSRect(x: x, y: y + yOff, width: width, height: 18)
            lbl.font = .systemFont(ofSize: 12, weight: .medium)
            lbl.textColor = .secondaryLabelColor
            view.addSubview(lbl)
            return lbl
        }

        func section(_ title: String) {
            let lbl = NSTextField(labelWithString: title.uppercased())
            lbl.frame = NSRect(x: 20, y: y, width: 380, height: 16)
            lbl.font = .systemFont(ofSize: 10, weight: .semibold)
            lbl.textColor = .tertiaryLabelColor
            view.addSubview(lbl)
            y -= 26
        }

        func separator() {
            let line = NSBox()
            line.boxType = .separator
            line.frame = NSRect(x: 20, y: y + 4, width: 380, height: 1)
            view.addSubview(line)
            y -= 16
        }

        // ── Title ──────────────────────────────────────────────────────────
        let titleLbl = NSTextField(labelWithString: "Now Playing Remote")
        titleLbl.frame = NSRect(x: 20, y: y, width: 300, height: 24)
        titleLbl.font = .systemFont(ofSize: 16, weight: .bold)
        view.addSubview(titleLbl)
        y -= 36

        // ── Server ────────────────────────────────────────────────────────
        section("Server")

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: y, width: 380, height: 18)
        statusLabel.font = .systemFont(ofSize: 12)
        view.addSubview(statusLabel)
        y -= 22

        urlLabel = NSTextField(labelWithString: "")
        urlLabel.frame = NSRect(x: 20, y: y, width: 280, height: 18)
        urlLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        urlLabel.textColor = .linkColor
        urlLabel.isSelectable = true
        view.addSubview(urlLabel)

        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyURL))
        copyBtn.frame = NSRect(x: 310, y: y - 2, width: 90, height: 22)
        copyBtn.bezelStyle = .rounded
        copyBtn.controlSize = .small
        view.addSubview(copyBtn)
        y -= 32

        // Port row
        addLabel("Port", x: 20, width: 60)
        portField.frame = NSRect(x: 80, y: y, width: 70, height: 22)
        portField.stringValue = String(settings.port)
        portField.formatter = {
            let f = NumberFormatter()
            f.minimum = 1024; f.maximum = 65535
            return f
        }()
        portField.isEditable = true
        view.addSubview(portField)

        portStepper.frame = NSRect(x: 155, y: y, width: 22, height: 22)
        portStepper.minValue = 1024; portStepper.maxValue = 65535
        portStepper.increment = 1
        portStepper.integerValue = settings.port
        portStepper.target = self; portStepper.action = #selector(portStepperChanged)
        view.addSubview(portStepper)

        applyPortBtn = NSButton(title: "Apply", target: self, action: #selector(applyPort))
        applyPortBtn.frame = NSRect(x: 185, y: y, width: 70, height: 22)
        applyPortBtn.bezelStyle = .rounded
        applyPortBtn.controlSize = .small
        view.addSubview(applyPortBtn)

        serverToggleBtn = NSButton(title: "", target: self, action: #selector(toggleServer))
        serverToggleBtn.frame = NSRect(x: 265, y: y, width: 115, height: 22)
        serverToggleBtn.bezelStyle = .rounded
        serverToggleBtn.controlSize = .small
        view.addSubview(serverToggleBtn)
        y -= 36

        // ── Startup ───────────────────────────────────────────────────────
        separator()
        section("Startup")

        autoStartCheck = checkbox("Start server automatically on launch", y: y)
        autoStartCheck.state = settings.autoStartServer ? .on : .off
        autoStartCheck.target = self; autoStartCheck.action = #selector(autoStartChanged)
        view.addSubview(autoStartCheck)
        y -= 26

        launchLoginCheck = checkbox("Launch at login", y: y)
        launchLoginCheck.state = settings.launchAtLogin ? .on : .off
        launchLoginCheck.target = self; launchLoginCheck.action = #selector(launchLoginChanged)
        view.addSubview(launchLoginCheck)
        y -= 36

        // ── Player ────────────────────────────────────────────────────────
        separator()
        section("Player")

        addLabel("Skip interval", x: 20, width: 100)
        skipPopup = NSPopUpButton(frame: NSRect(x: 130, y: y - 2, width: 110, height: 24), pullsDown: false)
        skipPopup.addItems(withTitles: ["5 seconds", "10 seconds", "15 seconds", "30 seconds"])
        let skipMap = [5: 0, 10: 1, 15: 2, 30: 3]
        skipPopup.selectItem(at: skipMap[settings.skipInterval] ?? 2)
        skipPopup.target = self; skipPopup.action = #selector(skipChanged)
        view.addSubview(skipPopup)
        y -= 32

        volumeCheck = checkbox("Show volume control", y: y)
        volumeCheck.state = settings.showVolumeControl ? .on : .off
        volumeCheck.target = self; volumeCheck.action = #selector(volumeChanged)
        view.addSubview(volumeCheck)
        y -= 26

        likeCheck = checkbox("Show like button", y: y)
        likeCheck.state = settings.showLikeButton ? .on : .off
        likeCheck.target = self; likeCheck.action = #selector(likeChanged)
        view.addSubview(likeCheck)
        y -= 26

        lyricsCheck = checkbox("Show lyrics", y: y)
        lyricsCheck.state = settings.showLyrics ? .on : .off
        lyricsCheck.target = self; lyricsCheck.action = #selector(lyricsChanged)
        view.addSubview(lyricsCheck)
        y -= 40

        // ── Custom Player ─────────────────────────────────────────────────
        separator()
        section("Custom Player")

        addLabel("Theme", x: 20, width: 80)
        themePopup = NSPopUpButton(frame: NSRect(x: 100, y: y - 2, width: 200, height: 24), pullsDown: false)
        themePopup.addItems(withTitles: ThemeID.allCases.map { $0.displayName })
        if let idx = ThemeID.allCases.firstIndex(of: settings.selectedTheme) {
            themePopup.selectItem(at: idx)
        }
        themePopup.target = self; themePopup.action = #selector(themeChanged)
        view.addSubview(themePopup)
        y -= 34

        customFileLabel = NSTextField(labelWithString: customPlayerStatusText())
        customFileLabel.frame = NSRect(x: 20, y: y, width: 380, height: 18)
        customFileLabel.font = .systemFont(ofSize: 12)
        customFileLabel.textColor = (settings.customPlayerHTML != nil || settings.customPlayerJS != nil) ? .systemGreen : .secondaryLabelColor
        view.addSubview(customFileLabel)
        y -= 30

        let importBtn = NSButton(title: "Import HTML/JS File…", target: self, action: #selector(importCustomFile))
        importBtn.frame = NSRect(x: 20, y: y, width: 175, height: 24)
        importBtn.bezelStyle = .rounded
        importBtn.controlSize = .small
        view.addSubview(importBtn)

        resetCustomBtn = NSButton(title: "Reset to Default", target: self, action: #selector(resetCustomPlayer))
        resetCustomBtn.frame = NSRect(x: 205, y: y, width: 140, height: 24)
        resetCustomBtn.bezelStyle = .rounded
        resetCustomBtn.controlSize = .small
        resetCustomBtn.isEnabled = settings.customPlayerHTML != nil || settings.customPlayerJS != nil
        view.addSubview(resetCustomBtn)
        y -= 40

        // ── Footer ────────────────────────────────────────────────────────
        separator()
        let note = NSTextField(wrappingLabelWithString: "Changes to port, volume, or like button require restarting the server.")
        note.frame = NSRect(x: 20, y: 10, width: 380, height: 34)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        view.addSubview(note)
    }

    private func checkbox(_ title: String, y: CGFloat) -> NSButton {
        let btn = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        btn.frame = NSRect(x: 20, y: y, width: 380, height: 20)
        btn.font = .systemFont(ofSize: 13)
        return btn
    }

    private func customPlayerStatusText() -> String {
        if let name = settings.customPlayerFileName ?? settings.customPlayerJSFileName {
            return "Active: \(name)"
        } else if settings.customPlayerHTML != nil || settings.customPlayerJS != nil {
            return "Custom player active"
        }
        return "No custom player set"
    }

    // MARK: - Refresh

    private func refresh() {
        let running = httpServer.isRunning
        statusLabel.stringValue = running
            ? "● Server running on port \(httpServer.currentPort)"
            : "○ Server stopped"
        statusLabel.textColor = running ? .systemGreen : .secondaryLabelColor

        if running {
            let ip = getLocalIP() ?? "localhost"
            urlLabel.stringValue = "http://\(ip):\(httpServer.currentPort)"
        } else {
            urlLabel.stringValue = ""
        }

        serverToggleBtn.title = running ? "Stop Server" : "Start Server"
        applyPortBtn.isEnabled = !running
    }

    // MARK: - Actions

    @objc private func toggleServer() {
        if httpServer.isRunning {
            httpServer.stop()
        } else {
            let port = portField.integerValue > 0 ? portField.integerValue : settings.port
            try? httpServer.start(port: port)
        }
        refresh()
    }

    @objc private func applyPort() {
        guard !httpServer.isRunning else { return }
        let newPort = portField.integerValue
        guard newPort >= 1024 && newPort <= 65535 else { return }
        settings.port = newPort
        portStepper.integerValue = newPort
    }

    @objc private func portStepperChanged() {
        portField.stringValue = String(portStepper.integerValue)
    }

    @objc private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlLabel.stringValue, forType: .string)
    }

    @objc private func autoStartChanged() {
        settings.autoStartServer = autoStartCheck.state == .on
    }

    @objc private func launchLoginChanged() {
        settings.launchAtLogin = launchLoginCheck.state == .on
    }

    @objc private func skipChanged() {
        let vals = [5, 10, 15, 30]
        settings.skipInterval = vals[skipPopup.indexOfSelectedItem]
    }

    @objc private func volumeChanged() {
        settings.showVolumeControl = volumeCheck.state == .on
    }

    @objc private func likeChanged() {
        settings.showLikeButton = likeCheck.state == .on
    }

    @objc private func lyricsChanged() {
        settings.showLyrics = lyricsCheck.state == .on
    }

    @objc private func themeChanged() {
        let idx = themePopup.indexOfSelectedItem
        guard idx >= 0 && idx < ThemeID.allCases.count else { return }
        settings.selectedTheme = ThemeID.allCases[idx]
    }

    @objc private func importCustomFile() {
        let panel = NSOpenPanel()
        panel.title = "Select HTML or JS Player File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.html, .javaScript]
        } else {
            panel.allowedFileTypes = ["html", "htm", "js"]
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let ext = url.pathExtension.lowercased()
                if ext == "js" {
                    self.settings.customPlayerJS = content
                    self.settings.customPlayerJSFileName = url.lastPathComponent
                    self.settings.customPlayerHTML = nil
                    self.settings.customPlayerFileName = nil
                } else {
                    self.settings.customPlayerHTML = content
                    self.settings.customPlayerFileName = url.lastPathComponent
                    self.settings.customPlayerJS = nil
                    self.settings.customPlayerJSFileName = nil
                }
                DispatchQueue.main.async {
                    self.customFileLabel.stringValue = self.customPlayerStatusText()
                    self.customFileLabel.textColor = .systemGreen
                    self.resetCustomBtn.isEnabled = true
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Could not read file"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    @objc private func resetCustomPlayer() {
        settings.customPlayerHTML = nil
        settings.customPlayerFileName = nil
        settings.customPlayerJS = nil
        settings.customPlayerJSFileName = nil
        customFileLabel.stringValue = "No custom player set"
        customFileLabel.textColor = .secondaryLabelColor
        resetCustomBtn.isEnabled = false
    }

    // MARK: - Helpers

    private func getLocalIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = first
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            if flags & IFF_LOOPBACK == 0, flags & IFF_UP != 0,
               ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var h = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                               &h, socklen_t(h.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: h)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }
        return nil
    }
}
