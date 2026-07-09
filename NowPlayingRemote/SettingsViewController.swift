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

    var supportsSkipInterval: Bool {
        if case .theme(let t) = self { return t.supportsSkipInterval }
        return false
    }

    var supportsVolumeControl: Bool {
        if case .theme(let t) = self { return t.supportsVolumeControl }
        return false
    }
}

final class SettingsViewController: NSViewController {

    private let httpServer: HTTPServer
    private let settings: SettingsManager

    // MARK: - Server controls
    private var portField        = NSTextField()
    private var portStepper      = NSStepper()
    private var serverToggleBtn  = NSButton()
    private var statusLabel      = NSTextField()
    private var urlLabel         = NSTextField()
    private var applyPortBtn     = NSButton()

    // MARK: - Startup toggles
    private var autoStartSwitch   = NSSwitch()
    private var launchLoginSwitch = NSSwitch()

    // MARK: - Player section (static)
    private var themeLabel        = NSTextField()
    private var themePopup        = NSPopUpButton()

    // MARK: - Player section (dynamic)
    private var skipLabel         = NSTextField()
    private var skipPopup         = NSPopUpButton()
    private var volumeLbl         = NSTextField()
    private var volumeSwitch      = NSSwitch()
    private var lyricsLbl         = NSTextField()
    private var lyricsSwitch      = NSSwitch()
    private var lyricsAutoHideLbl = NSTextField()
    private var lyricsAutoHideSwitch = NSSwitch()

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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))
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

    // MARK: - Layout helpers

    private func makeGroupBox(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> NSView {
        let v = NSView(frame: NSRect(x: x, y: y, width: w, height: h))
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.06).cgColor
        v.layer?.cornerRadius = 10
        v.layer?.borderColor = NSColor(white: 0.7, alpha: 0.12).cgColor
        v.layer?.borderWidth = 0.5
        return v
    }

    private func addRowSep(in parent: NSView, atY y: CGFloat) {
        let sep = NSBox(); sep.boxType = .separator
        sep.frame = NSRect(x: 14, y: y, width: parent.frame.width - 28, height: 1)
        parent.addSubview(sep)
    }

    private func rowLabel(_ text: String, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13)
        l.textColor = color
        return l
    }

    // MARK: - UI Construction

    private func buildUI() {
        let W: CGFloat = 460
        var y: CGFloat = 662

        func sectionHeader(_ title: String) {
            let lbl = NSTextField(labelWithString: title.uppercased())
            lbl.frame = NSRect(x: 20, y: y, width: W - 40, height: 14)
            lbl.font = .systemFont(ofSize: 10, weight: .semibold)
            lbl.textColor = .tertiaryLabelColor
            view.addSubview(lbl)
            y -= 22
        }

        // ── Title ─────────────────────────────────────────────────────────────
        let titleLbl = NSTextField(labelWithString: "Now Playing Remote")
        titleLbl.frame = NSRect(x: 20, y: y, width: W - 40, height: 26)
        titleLbl.font = .systemFont(ofSize: 17, weight: .semibold)
        view.addSubview(titleLbl)
        y -= 42

        // ── Server ────────────────────────────────────────────────────────────
        sectionHeader("Server")

        let srvH: CGFloat = 118
        let srvBox = makeGroupBox(x: 16, y: y - srvH, w: W - 32, h: srvH)
        view.addSubview(srvBox)
        let bW = srvBox.frame.width

        // Row 1 (top): status + toggle button
        statusLabel.frame = NSRect(x: 14, y: 85, width: bW - 132, height: 20)
        statusLabel.font = .systemFont(ofSize: 13)
        srvBox.addSubview(statusLabel)

        serverToggleBtn = NSButton(title: "", target: self, action: #selector(toggleServer))
        serverToggleBtn.frame = NSRect(x: bW - 116, y: 83, width: 102, height: 22)
        serverToggleBtn.bezelStyle = .rounded; serverToggleBtn.controlSize = .small
        srvBox.addSubview(serverToggleBtn)

        addRowSep(in: srvBox, atY: 78)

        // Row 2: URL + copy
        urlLabel.frame = NSRect(x: 14, y: 56, width: bW - 84, height: 18)
        urlLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        urlLabel.textColor = .linkColor
        urlLabel.isSelectable = true
        srvBox.addSubview(urlLabel)

        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyURL))
        copyBtn.frame = NSRect(x: bW - 70, y: 54, width: 56, height: 22)
        copyBtn.bezelStyle = .rounded; copyBtn.controlSize = .small
        srvBox.addSubview(copyBtn)

        addRowSep(in: srvBox, atY: 40)

        // Row 3 (bottom): port
        let portLbl = rowLabel("Port", color: .secondaryLabelColor)
        portLbl.frame = NSRect(x: 14, y: 12, width: 40, height: 20)
        srvBox.addSubview(portLbl)

        portField.frame = NSRect(x: 60, y: 11, width: 64, height: 22)
        portField.stringValue = String(settings.port)
        portField.formatter = { let f = NumberFormatter(); f.minimum = 1024; f.maximum = 65535; return f }()
        portField.isEditable = true
        srvBox.addSubview(portField)

        portStepper.frame = NSRect(x: 128, y: 11, width: 22, height: 22)
        portStepper.minValue = 1024; portStepper.maxValue = 65535; portStepper.increment = 1
        portStepper.integerValue = settings.port
        portStepper.target = self; portStepper.action = #selector(portStepperChanged)
        srvBox.addSubview(portStepper)

        applyPortBtn = NSButton(title: "Apply", target: self, action: #selector(applyPort))
        applyPortBtn.frame = NSRect(x: 156, y: 11, width: 60, height: 22)
        applyPortBtn.bezelStyle = .rounded; applyPortBtn.controlSize = .small
        srvBox.addSubview(applyPortBtn)

        y -= srvH + 18

        // ── Startup ───────────────────────────────────────────────────────────
        sectionHeader("Startup")

        let stH: CGFloat = 88
        let stBox = makeGroupBox(x: 16, y: y - stH, w: W - 32, h: stH)
        view.addSubview(stBox)
        let stW = stBox.frame.width

        let asLbl = rowLabel("Start server automatically on launch")
        asLbl.frame = NSRect(x: 14, y: 55, width: stW - 80, height: 20)
        stBox.addSubview(asLbl)
        autoStartSwitch.state = settings.autoStartServer ? .on : .off
        autoStartSwitch.target = self; autoStartSwitch.action = #selector(autoStartChanged)
        autoStartSwitch.frame = NSRect(x: stW - 58, y: 52, width: 44, height: 26)
        stBox.addSubview(autoStartSwitch)

        addRowSep(in: stBox, atY: 44)

        let llLbl = rowLabel("Launch at login")
        llLbl.frame = NSRect(x: 14, y: 13, width: stW - 80, height: 20)
        stBox.addSubview(llLbl)
        launchLoginSwitch.state = settings.launchAtLogin ? .on : .off
        launchLoginSwitch.target = self; launchLoginSwitch.action = #selector(launchLoginChanged)
        launchLoginSwitch.frame = NSRect(x: stW - 58, y: 10, width: 44, height: 26)
        stBox.addSubview(launchLoginSwitch)

        y -= stH + 18

        // ── Player ────────────────────────────────────────────────────────────
        sectionHeader("Player")

        let thmLbl = rowLabel("Theme", color: .secondaryLabelColor)
        thmLbl.frame = NSRect(x: 20, y: y, width: 70, height: 18)
        view.addSubview(thmLbl)
        themeLabel = thmLbl

        themePopup = NSPopUpButton(frame: NSRect(x: 90, y: y - 2, width: W - 110, height: 24), pullsDown: false)
        themePopup.addItems(withTitles: PlayerSelection.allCases.map { $0.displayName })
        let selIdx = PlayerSelection.allCases.firstIndex(of: currentSelection) ?? 0
        themePopup.selectItem(at: selIdx)
        themePopup.target = self; themePopup.action = #selector(themePickerChanged)
        view.addSubview(themePopup)
        y -= 36

        // Dynamic controls — all initially positioned at y; updateDynamicSection repositions them.
        skipLabel = rowLabel("Skip interval", color: .secondaryLabelColor)
        skipLabel.frame = NSRect(x: 20, y: y, width: 110, height: 18)
        view.addSubview(skipLabel)

        skipPopup = NSPopUpButton(frame: NSRect(x: 140, y: y - 2, width: 150, height: 24), pullsDown: false)
        skipPopup.addItems(withTitles: ["5 seconds", "10 seconds", "15 seconds", "30 seconds"])
        let skipMap = [5: 0, 10: 1, 15: 2, 30: 3]
        skipPopup.selectItem(at: skipMap[settings.skipInterval] ?? 2)
        skipPopup.target = self; skipPopup.action = #selector(skipChanged)
        view.addSubview(skipPopup)

        volumeLbl = rowLabel("Show volume control")
        volumeLbl.frame = NSRect(x: 20, y: y, width: W - 100, height: 20)
        view.addSubview(volumeLbl)
        volumeSwitch.state = settings.showVolumeControl ? .on : .off
        volumeSwitch.target = self; volumeSwitch.action = #selector(volumeChanged)
        volumeSwitch.frame = NSRect(x: W - 64, y: y - 2, width: 44, height: 26)
        view.addSubview(volumeSwitch)

        lyricsLbl = rowLabel("Show lyrics")
        lyricsLbl.frame = NSRect(x: 20, y: y, width: W - 100, height: 20)
        view.addSubview(lyricsLbl)
        lyricsSwitch.state = settings.showLyrics ? .on : .off
        lyricsSwitch.target = self; lyricsSwitch.action = #selector(lyricsChanged)
        lyricsSwitch.frame = NSRect(x: W - 64, y: y - 2, width: 44, height: 26)
        view.addSubview(lyricsSwitch)

        lyricsAutoHideLbl = rowLabel("Auto-hide when no lyrics found")
        lyricsAutoHideLbl.frame = NSRect(x: 20, y: y, width: W - 100, height: 20)
        view.addSubview(lyricsAutoHideLbl)
        lyricsAutoHideSwitch.state = settings.lyricsAutoHide ? .on : .off
        lyricsAutoHideSwitch.target = self; lyricsAutoHideSwitch.action = #selector(lyricsAutoHideChanged)
        lyricsAutoHideSwitch.frame = NSRect(x: W - 64, y: y - 2, width: 44, height: 26)
        view.addSubview(lyricsAutoHideSwitch)

        customFileLabel.frame = NSRect(x: 20, y: y, width: W - 40, height: 18)
        customFileLabel.font = .systemFont(ofSize: 13)
        view.addSubview(customFileLabel)

        importBtn = NSButton(title: "Import File…", target: self, action: #selector(importCustomFile))
        importBtn.frame = NSRect(x: 20, y: y - 26, width: 150, height: 24)
        importBtn.bezelStyle = .rounded; importBtn.controlSize = .small
        view.addSubview(importBtn)

        resetCustomBtn = NSButton(title: "Clear", target: self, action: #selector(resetCustomPlayer))
        resetCustomBtn.frame = NSRect(x: 180, y: y - 26, width: 80, height: 24)
        resetCustomBtn.bezelStyle = .rounded; resetCustomBtn.controlSize = .small
        view.addSubview(resetCustomBtn)

        // ── Footer ────────────────────────────────────────────────────────────
        footerBox = NSBox(); footerBox.boxType = .separator
        footerBox.frame = NSRect(x: 20, y: 40, width: W - 40, height: 1)
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

        let fileName: String?
        if currentSelection == .customHTML {
            fileName = settings.customPlayerFileName
        } else if currentSelection == .customJS {
            fileName = settings.customPlayerJSFileName
        } else {
            fileName = nil
        }

        let showSkip     = !isCustom && currentSelection.supportsSkipInterval
        let showVol      = !isCustom && currentSelection.supportsVolumeControl
        let showLyr      = !isCustom && supportsLyr
        let showAutoHide = showLyr && settings.showLyrics

        skipLabel.isHidden           = !showSkip
        skipPopup.isHidden           = !showSkip
        volumeLbl.isHidden           = !showVol
        volumeSwitch.isHidden        = !showVol
        lyricsLbl.isHidden           = !showLyr
        lyricsSwitch.isHidden        = !showLyr
        lyricsAutoHideLbl.isHidden   = !showAutoHide
        lyricsAutoHideSwitch.isHidden = !showAutoHide
        customFileLabel.isHidden     = !isCustom
        importBtn.isHidden           = !isCustom
        resetCustomBtn.isHidden      = !isCustom

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

        // Reposition all dynamic controls below theme popup
        let W   = view.frame.width
        let topY = themePopup.frame.minY - 8
        var y    = topY
        let rowH: CGFloat = 34
        let swX  = W - 64

        func switchRow(_ lbl: NSTextField, _ sw: NSSwitch) {
            guard !lbl.isHidden else { return }
            y -= rowH
            lbl.frame = NSRect(x: 20, y: y + 7, width: W - 100, height: 20)
            sw.frame  = NSRect(x: swX, y: y + 4, width: 44, height: 26)
            y -= 4
        }

        if showSkip {
            y -= rowH
            skipLabel.frame = NSRect(x: 20, y: y + 8, width: 110, height: 18)
            skipPopup.frame = NSRect(x: 140, y: y + 5, width: 150, height: 24)
            y -= 4
        }

        switchRow(volumeLbl, volumeSwitch)
        switchRow(lyricsLbl, lyricsSwitch)
        switchRow(lyricsAutoHideLbl, lyricsAutoHideSwitch)

        if isCustom {
            y -= 24
            customFileLabel.frame = NSRect(x: 20, y: y, width: W - 40, height: 18)
            y -= 8
            importBtn.frame     = NSRect(x: 20,  y: y - 24, width: 150, height: 24)
            resetCustomBtn.frame = NSRect(x: 180, y: y - 24, width: 80,  height: 24)
            y -= 34
        }

        footerBox.frame = NSRect(x: 20, y: y - 14, width: W - 40, height: 1)
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

    @objc private func autoStartChanged()    { settings.autoStartServer  = autoStartSwitch.state == .on }
    @objc private func launchLoginChanged()  { settings.launchAtLogin    = launchLoginSwitch.state == .on }
    @objc private func skipChanged()         { settings.skipInterval     = [5,10,15,30][skipPopup.indexOfSelectedItem] }
    @objc private func volumeChanged()       { settings.showVolumeControl = volumeSwitch.state == .on }

    @objc private func lyricsChanged() {
        settings.showLyrics = lyricsSwitch.state == .on
        updateDynamicSection()
    }

    @objc private func lyricsAutoHideChanged() {
        settings.lyricsAutoHide = lyricsAutoHideSwitch.state == .on
    }

    @objc private func themePickerChanged() {
        let idx = themePopup.indexOfSelectedItem
        let all = PlayerSelection.allCases
        guard idx >= 0 && idx < all.count else { return }
        currentSelection = all[idx]

        switch currentSelection {
        case .theme(let t):
            settings.selectedTheme = t
            settings.customPlayerHTML = nil
            settings.customPlayerFileName = nil
            settings.customPlayerJS = nil
            settings.customPlayerJSFileName = nil
        case .customHTML, .customJS:
            break
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
