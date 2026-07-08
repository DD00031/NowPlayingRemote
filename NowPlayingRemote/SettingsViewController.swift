import AppKit
import Darwin
import UniformTypeIdentifiers

// Extends ThemeID with two extra "virtual" picker entries for custom files.
private enum PlayerSelection: Equatable {
    case theme(ThemeID)
    case customHTML
    case customJS

    var displayName: String {
        switch self {
        case .theme(let t): return t.displayName
        case .customHTML:   return "Custom HTML File"
        case .customJS:     return "Custom JS File"
        }
    }

    static var allCases: [PlayerSelection] {
        ThemeID.allCases.map { .theme($0) } + [.customHTML, .customJS]
    }

    var supportsLyrics: Bool {
        if case .theme(let t) = self { return t.supportsLyrics }
        return false
    }
}

final class SettingsViewController: NSViewController {

    private let httpServer: HTTPServer
    private let settings: SettingsManager

    // MARK: - Persistent controls (always visible)
    private var portField        = NSTextField()
    private var portStepper      = NSStepper()
    private var autoStartCheck   = NSButton()
    private var launchLoginCheck = NSButton()
    private var serverToggleBtn  = NSButton()
    private var statusLabel      = NSTextField()
    private var urlLabel         = NSTextField()
    private var applyPortBtn     = NSButton()

    // MARK: - Player section (dynamic)
    private var playerSectionBox  = NSBox()        // separator
    private var playerSectionLbl  = NSTextField()  // "PLAYER" header
    private var themeLabel        = NSTextField()
    private var themePopup        = NSPopUpButton()

    // Theme-specific controls (shown/hidden dynamically)
    private var skipLabel         = NSTextField()
    private var skipPopup         = NSPopUpButton()
    private var volumeCheck       = NSButton()
    private var lyricsCheck       = NSButton()
    private var lyricsAutoHideCheck = NSButton()

    // Custom file controls
    private var customFileLabel   = NSTextField()
    private var importBtn         = NSButton()
    private var resetCustomBtn    = NSButton()

    private var footerBox         = NSBox()
    private var footerNote        = NSTextField()

    private var currentSelection: PlayerSelection = .theme(.clean)

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
        deriveCurrentSelection()
        buildUI()
        refreshServer()
        updateDynamicSection()
    }

    // MARK: - Derive selection from settings

    private func deriveCurrentSelection() {
        if settings.customPlayerHTML != nil {
            currentSelection = .customHTML
        } else if settings.customPlayerJS != nil {
            currentSelection = .customJS
        } else {
            currentSelection = .theme(settings.selectedTheme)
        }
    }

    // MARK: - UI Construction

    private func buildUI() {
        let W: CGFloat = 420
        var y: CGFloat = 660

        func label(_ text: String, x: CGFloat = 20, width: CGFloat = 380, size: CGFloat = 12, weight: NSFont.Weight = .medium, color: NSColor = .secondaryLabelColor) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.frame = NSRect(x: x, y: y, width: width, height: 18)
            lbl.font = .systemFont(ofSize: size, weight: weight)
            lbl.textColor = color
            view.addSubview(lbl)
            return lbl
        }

        func sectionHeader(_ title: String) {
            let sep = NSBox(); sep.boxType = .separator
            sep.frame = NSRect(x: 20, y: y + 4, width: W - 40, height: 1)
            view.addSubview(sep)
            y -= 16

            let lbl = NSTextField(labelWithString: title.uppercased())
            lbl.frame = NSRect(x: 20, y: y, width: W - 40, height: 16)
            lbl.font = .systemFont(ofSize: 10, weight: .semibold)
            lbl.textColor = .tertiaryLabelColor
            view.addSubview(lbl)
            y -= 26
        }

        func checkbox(_ title: String) -> NSButton {
            let btn = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            btn.frame = NSRect(x: 20, y: y, width: W - 40, height: 20)
            btn.font = .systemFont(ofSize: 13)
            return btn
        }

        // ── App title ──────────────────────────────────────────────────────
        let titleLbl = NSTextField(labelWithString: "Now Playing Remote")
        titleLbl.frame = NSRect(x: 20, y: y, width: 300, height: 24)
        titleLbl.font = .systemFont(ofSize: 16, weight: .bold)
        view.addSubview(titleLbl)
        y -= 36

        // ── Server ──────────────────────────────────────────────────────
        let _ = sectionHeader("Server")  // inline — moves y

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: y, width: W - 40, height: 18)
        statusLabel.font = .systemFont(ofSize: 12)
        view.addSubview(statusLabel)
        y -= 22

        urlLabel = NSTextField(labelWithString: "")
        urlLabel.frame = NSRect(x: 20, y: y, width: 270, height: 18)
        urlLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        urlLabel.textColor = .linkColor
        urlLabel.isSelectable = true
        view.addSubview(urlLabel)

        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyURL))
        copyBtn.frame = NSRect(x: 300, y: y - 2, width: 100, height: 22)
        copyBtn.bezelStyle = .rounded; copyBtn.controlSize = .small
        view.addSubview(copyBtn)
        y -= 32

        // Port row
        let portLbl = NSTextField(labelWithString: "Port")
        portLbl.frame = NSRect(x: 20, y: y, width: 60, height: 18)
        portLbl.font = .systemFont(ofSize: 12, weight: .medium)
        portLbl.textColor = .secondaryLabelColor
        view.addSubview(portLbl)

        portField.frame = NSRect(x: 80, y: y, width: 70, height: 22)
        portField.stringValue = String(settings.port)
        portField.formatter = { let f = NumberFormatter(); f.minimum = 1024; f.maximum = 65535; return f }()
        portField.isEditable = true
        view.addSubview(portField)

        portStepper.frame = NSRect(x: 155, y: y, width: 22, height: 22)
        portStepper.minValue = 1024; portStepper.maxValue = 65535; portStepper.increment = 1
        portStepper.integerValue = settings.port
        portStepper.target = self; portStepper.action = #selector(portStepperChanged)
        view.addSubview(portStepper)

        applyPortBtn = NSButton(title: "Apply", target: self, action: #selector(applyPort))
        applyPortBtn.frame = NSRect(x: 185, y: y, width: 70, height: 22)
        applyPortBtn.bezelStyle = .rounded; applyPortBtn.controlSize = .small
        view.addSubview(applyPortBtn)

        serverToggleBtn = NSButton(title: "", target: self, action: #selector(toggleServer))
        serverToggleBtn.frame = NSRect(x: 265, y: y, width: 115, height: 22)
        serverToggleBtn.bezelStyle = .rounded; serverToggleBtn.controlSize = .small
        view.addSubview(serverToggleBtn)
        y -= 36

        // ── Startup ──────────────────────────────────────────────────────
        let _ = sectionHeader("Startup")

        autoStartCheck = checkbox("Start server automatically on launch")
        autoStartCheck.state = settings.autoStartServer ? .on : .off
        autoStartCheck.target = self; autoStartCheck.action = #selector(autoStartChanged)
        view.addSubview(autoStartCheck)
        y -= 26

        launchLoginCheck = checkbox("Launch at login")
        launchLoginCheck.state = settings.launchAtLogin ? .on : .off
        launchLoginCheck.target = self; launchLoginCheck.action = #selector(launchLoginChanged)
        view.addSubview(launchLoginCheck)
        y -= 36

        // ── Player ──────────────────────────────────────────────────────
        let playerSep = NSBox(); playerSep.boxType = .separator
        playerSep.frame = NSRect(x: 20, y: y + 4, width: W - 40, height: 1)
        view.addSubview(playerSep)
        y -= 16

        playerSectionLbl = NSTextField(labelWithString: "PLAYER")
        playerSectionLbl.frame = NSRect(x: 20, y: y, width: W - 40, height: 16)
        playerSectionLbl.font = .systemFont(ofSize: 10, weight: .semibold)
        playerSectionLbl.textColor = .tertiaryLabelColor
        view.addSubview(playerSectionLbl)
        y -= 28

        // Theme picker row
        themeLabel = NSTextField(labelWithString: "Theme")
        themeLabel.frame = NSRect(x: 20, y: y, width: 80, height: 18)
        themeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        themeLabel.textColor = .secondaryLabelColor
        view.addSubview(themeLabel)

        themePopup = NSPopUpButton(frame: NSRect(x: 100, y: y - 2, width: W - 120, height: 24), pullsDown: false)
        themePopup.addItems(withTitles: PlayerSelection.allCases.map { $0.displayName })
        let selIdx = PlayerSelection.allCases.firstIndex(of: currentSelection) ?? 0
        themePopup.selectItem(at: selIdx)
        themePopup.target = self; themePopup.action = #selector(themePickerChanged)
        view.addSubview(themePopup)
        y -= 34

        // ── Dynamic controls (positioned relative to current y) ──────────
        // All start at y; updateDynamicSection will show/hide + reposition them.

        // Skip interval
        skipLabel = NSTextField(labelWithString: "Skip interval")
        skipLabel.frame = NSRect(x: 20, y: y, width: 100, height: 18)
        skipLabel.font = .systemFont(ofSize: 12, weight: .medium)
        skipLabel.textColor = .secondaryLabelColor
        view.addSubview(skipLabel)

        skipPopup = NSPopUpButton(frame: NSRect(x: 130, y: y - 2, width: 130, height: 24), pullsDown: false)
        skipPopup.addItems(withTitles: ["5 seconds", "10 seconds", "15 seconds", "30 seconds"])
        let skipMap = [5: 0, 10: 1, 15: 2, 30: 3]
        skipPopup.selectItem(at: skipMap[settings.skipInterval] ?? 2)
        skipPopup.target = self; skipPopup.action = #selector(skipChanged)
        view.addSubview(skipPopup)
        y -= 32

        volumeCheck = checkbox("Show volume control")
        volumeCheck.state = settings.showVolumeControl ? .on : .off
        volumeCheck.target = self; volumeCheck.action = #selector(volumeChanged)
        view.addSubview(volumeCheck)
        y -= 26

        lyricsCheck = checkbox("Show lyrics")
        lyricsCheck.state = settings.showLyrics ? .on : .off
        lyricsCheck.target = self; lyricsCheck.action = #selector(lyricsChanged)
        view.addSubview(lyricsCheck)
        y -= 26

        lyricsAutoHideCheck = checkbox("Auto-hide lyrics when none found")
        lyricsAutoHideCheck.state = settings.lyricsAutoHide ? .on : .off
        lyricsAutoHideCheck.target = self; lyricsAutoHideCheck.action = #selector(lyricsAutoHideChanged)
        view.addSubview(lyricsAutoHideCheck)
        y -= 34

        // Custom file controls
        customFileLabel = NSTextField(labelWithString: "")
        customFileLabel.frame = NSRect(x: 20, y: y, width: W - 40, height: 18)
        customFileLabel.font = .systemFont(ofSize: 12)
        view.addSubview(customFileLabel)
        y -= 28

        importBtn = NSButton(title: "Import File…", target: self, action: #selector(importCustomFile))
        importBtn.frame = NSRect(x: 20, y: y, width: 140, height: 24)
        importBtn.bezelStyle = .rounded; importBtn.controlSize = .small
        view.addSubview(importBtn)

        resetCustomBtn = NSButton(title: "Clear", target: self, action: #selector(resetCustomPlayer))
        resetCustomBtn.frame = NSRect(x: 170, y: y, width: 80, height: 24)
        resetCustomBtn.bezelStyle = .rounded; resetCustomBtn.controlSize = .small
        view.addSubview(resetCustomBtn)
        y -= 40

        // ── Footer ──────────────────────────────────────────────────────
        footerBox = NSBox(); footerBox.boxType = .separator
        footerBox.frame = NSRect(x: 20, y: y + 4, width: W - 40, height: 1)
        view.addSubview(footerBox)

        footerNote = NSTextField(wrappingLabelWithString: "Changes to port or volume control require restarting the server.")
        footerNote.frame = NSRect(x: 20, y: 10, width: W - 40, height: 34)
        footerNote.font = .systemFont(ofSize: 11)
        footerNote.textColor = .tertiaryLabelColor
        view.addSubview(footerNote)
    }

    // MARK: - Dynamic section

    private func updateDynamicSection() {
        let isCustom = (currentSelection == .customHTML || currentSelection == .customJS)
        let supportsLyr = currentSelection.supportsLyrics

        // Determine file label text + color
        let fileName: String?
        if currentSelection == .customHTML {
            fileName = settings.customPlayerFileName
        } else if currentSelection == .customJS {
            fileName = settings.customPlayerJSFileName
        } else {
            fileName = nil
        }

        // Show/hide built-in controls
        skipLabel.isHidden = isCustom
        skipPopup.isHidden = isCustom
        volumeCheck.isHidden = isCustom
        lyricsCheck.isHidden = isCustom || !supportsLyr
        lyricsAutoHideCheck.isHidden = isCustom || !supportsLyr || !settings.showLyrics

        // Show/hide custom controls
        customFileLabel.isHidden = !isCustom
        importBtn.isHidden = !isCustom
        resetCustomBtn.isHidden = !isCustom

        if isCustom {
            if let name = fileName {
                customFileLabel.stringValue = "Active: \(name)"
                customFileLabel.textColor = .systemGreen
            } else {
                let ext = currentSelection == .customHTML ? "HTML" : "JS"
                customFileLabel.stringValue = "No \(ext) file imported"
                customFileLabel.textColor = .secondaryLabelColor
            }
            importBtn.title = currentSelection == .customHTML ? "Import HTML File…" : "Import JS File…"
            resetCustomBtn.isEnabled = fileName != nil
        }

        // Now reposition all dynamic controls from top of dynamic area down
        // The dynamic area starts right below the theme popup row.
        // We need to find the bottom of the theme picker and lay out from there.
        // themePopup.frame.minY is the start of picker; dynamic content goes below.
        let topY = themePopup.frame.minY - 10  // 10px gap below picker

        var y = topY

        func reposition(_ view: NSView, height: CGFloat, gap: CGFloat) {
            guard !view.isHidden else { return }
            y -= height
            view.frame = NSRect(x: view.frame.minX, y: y, width: view.frame.width, height: height)
            y -= gap
        }

        // Skip row (label + popup together)
        if !skipLabel.isHidden {
            y -= 18
            let rowY = y
            skipLabel.frame = NSRect(x: 20, y: rowY, width: 100, height: 18)
            skipPopup.frame = NSRect(x: 130, y: rowY - 2, width: 130, height: 24)
            y -= 14   // total row height ~32
        }

        reposition(volumeCheck, height: 20, gap: 6)
        reposition(lyricsCheck, height: 20, gap: 6)
        reposition(lyricsAutoHideCheck, height: 20, gap: 10)

        // Custom file label
        if !customFileLabel.isHidden {
            y -= 18
            customFileLabel.frame = NSRect(x: 20, y: y, width: themePopup.frame.width + themePopup.frame.minX - 20, height: 18)
            y -= 10
            importBtn.frame = NSRect(x: 20, y: y - 24, width: 160, height: 24)
            resetCustomBtn.frame = NSRect(x: 190, y: y - 24, width: 80, height: 24)
            y -= 34
        }

        // Footer separator
        footerBox.frame = NSRect(x: 20, y: y - 4, width: 380, height: 1)
    }

    // MARK: - Server refresh

    private func refreshServer() {
        let running = httpServer.isRunning
        statusLabel.stringValue = running
            ? "● Server running on port \(httpServer.currentPort)"
            : "○ Server stopped"
        statusLabel.textColor = running ? .systemGreen : .secondaryLabelColor

        if running, let ip = getLocalIP() {
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
        refreshServer()
    }

    @objc private func applyPort() {
        guard !httpServer.isRunning else { return }
        let p = portField.integerValue
        guard p >= 1024 && p <= 65535 else { return }
        settings.port = p
        portStepper.integerValue = p
    }

    @objc private func portStepperChanged() {
        portField.stringValue = String(portStepper.integerValue)
    }

    @objc private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlLabel.stringValue, forType: .string)
    }

    @objc private func autoStartChanged() { settings.autoStartServer = autoStartCheck.state == .on }
    @objc private func launchLoginChanged() { settings.launchAtLogin = launchLoginCheck.state == .on }
    @objc private func skipChanged() { settings.skipInterval = [5,10,15,30][skipPopup.indexOfSelectedItem] }
    @objc private func volumeChanged() { settings.showVolumeControl = volumeCheck.state == .on }

    @objc private func lyricsChanged() {
        settings.showLyrics = lyricsCheck.state == .on
        updateDynamicSection()
    }

    @objc private func lyricsAutoHideChanged() {
        settings.lyricsAutoHide = lyricsAutoHideCheck.state == .on
    }

    @objc private func themePickerChanged() {
        let idx = themePopup.indexOfSelectedItem
        let all = PlayerSelection.allCases
        guard idx >= 0 && idx < all.count else { return }
        currentSelection = all[idx]

        switch currentSelection {
        case .theme(let t):
            settings.selectedTheme = t
            // Clear custom files so built-in theme is used
            settings.customPlayerHTML = nil
            settings.customPlayerFileName = nil
            settings.customPlayerJS = nil
            settings.customPlayerJSFileName = nil
        case .customHTML, .customJS:
            break  // file will be imported via importCustomFile
        }

        updateDynamicSection()
    }

    @objc private func importCustomFile() {
        let panel = NSOpenPanel()
        panel.title = currentSelection == .customHTML ? "Select HTML Player File" : "Select JS Player File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = currentSelection == .customHTML ? [.html] : [.javaScript]
        } else {
            panel.allowedFileTypes = currentSelection == .customHTML ? ["html","htm"] : ["js"]
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                if self.currentSelection == .customHTML {
                    self.settings.customPlayerHTML = content
                    self.settings.customPlayerFileName = url.lastPathComponent
                    self.settings.customPlayerJS = nil
                    self.settings.customPlayerJSFileName = nil
                } else {
                    self.settings.customPlayerJS = content
                    self.settings.customPlayerJSFileName = url.lastPathComponent
                    self.settings.customPlayerHTML = nil
                    self.settings.customPlayerFileName = nil
                }
                DispatchQueue.main.async { self.updateDynamicSection() }
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
        updateDynamicSection()
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
