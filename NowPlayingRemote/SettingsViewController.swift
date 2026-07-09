import AppKit
import Darwin
import UniformTypeIdentifiers

private enum PlayerSelection: Equatable {
    case theme(ThemeID)
    case themeArchive          // .theme ZIP archive (installed via ThemeArchiveManager)
    case customHTML
    case customJS

    var displayName: String {
        switch self {
        case .theme(let t):  return t.displayName
        case .themeArchive:
            return ThemeArchiveManager.shared.manifest().map { "\($0.name) (.theme)" }
                   ?? "Theme Archive (.theme)"
        case .customHTML:   return "Custom HTML File"
        case .customJS:     return "Custom JS File"
        }
    }

    static var allCases: [PlayerSelection] {
        ThemeID.allCases.map { .theme($0) } + [.themeArchive, .customHTML, .customJS]
    }

    var supportsLyrics: Bool {
        switch self {
        case .theme(let t):  return t.supportsLyrics
        case .themeArchive:  return ThemeArchiveManager.shared.manifest()?.supportsLyrics ?? false
        default:             return false
        }
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
    private var statusLabel      = NSTextField(labelWithString: "")
    private var urlLabel         = NSTextField(labelWithString: "")
    private var applyPortBtn     = NSButton()

    // MARK: - Startup toggles
    private var autoStartSwitch   = NSSwitch()
    private var launchLoginSwitch = NSSwitch()

    // MARK: - Player section controls
    private var themePopup        = NSPopUpButton()
    private var skipPopup         = NSPopUpButton()
    private var volumeSwitch      = NSSwitch()
    private var lyricsSwitch      = NSSwitch()
    private var lyricsAutoHideSwitch = NSSwitch()
    
    private var customFileLabel   = NSTextField(labelWithString: "")
    private var importBtn         = NSButton()
    private var resetCustomBtn    = NSButton()

    // Theme archive (.theme) controls
    private var themeArchiveLabel = NSTextField(labelWithString: "")
    private var importThemeBtn    = NSButton()
    private var removeThemeBtn    = NSButton()

    // MARK: - Layout Containers
    private var mainStack: NSStackView!
    private var playerVStack: NSStackView!

    private var themeRow: NSView!
    private var skipRow: NSView!
    private var volumeRow: NSView!
    private var lyricsRow: NSView!
    private var lyricsAutoHideRow: NSView!
    private var customFileRow: NSView!
    private var themeArchiveRow: NSView!
    private var themeWarningNote: NSTextField!

    private var currentSelection: PlayerSelection = .theme(.clean)

    init(httpServer: HTTPServer, settings: SettingsManager) {
        self.httpServer = httpServer
        self.settings   = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        
        // FIX 1: Enforce a vibrant dark appearance so the Mission Control snapshot never falls back to light grey
        effectView.appearance = NSAppearance(named: .vibrantDark)
        effectView.material = .underWindowBackground
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        
        view = effectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        deriveCurrentSelection()
        buildModernUI()
        refreshServer()
        updateDynamicSection()
    }

    // MARK: - Derive selection from settings

    private func deriveCurrentSelection() {
        if settings.customPlayerHTML != nil {
            currentSelection = .customHTML
        } else if settings.customPlayerJS != nil {
            currentSelection = .customJS
        } else if settings.useThemeArchive {
            currentSelection = .themeArchive
        } else {
            currentSelection = .theme(settings.selectedTheme)
        }
    }

    // MARK: - Modern UI Construction

    private func buildModernUI() {
        mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 24
        mainStack.alignment = .leading
        mainStack.edgeInsets = NSEdgeInsets(top: 30, left: 30, bottom: 40, right: 30)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Prevent the stack view from loosely expanding to fill window height
        mainStack.setContentHuggingPriority(.required, for: .vertical)

        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // FIX 2: Explicitly lock the window width to prevent horizontal expansion
            view.widthAnchor.constraint(equalToConstant: 500)
        ])

        // ── Title ─────────────────────────────────────────────────────────────
        let titleLbl = NSTextField(labelWithString: "Now Playing Remote")
        titleLbl.font = .systemFont(ofSize: 24, weight: .bold)
        mainStack.addArrangedSubview(titleLbl)

        // ── Form Sections ─────────────────────────────────────────────────────
        
        // SERVER SECTION
        mainStack.addArrangedSubview(createSectionHeader("SERVER"))
        let (serverCard, serverVStack) = createCard()
        mainStack.addArrangedSubview(serverCard)
        serverCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -60).isActive = true

        serverToggleBtn = NSButton(title: "Start", target: self, action: #selector(toggleServer))
        serverToggleBtn.bezelStyle = .push
        serverVStack.addArrangedSubview(createRow(title: "Status", labelOverride: statusLabel, controls: [serverToggleBtn]).0)

        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyURL))
        copyBtn.bezelStyle = .push
        urlLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        serverVStack.addArrangedSubview(createRow(title: "Address", labelOverride: urlLabel, controls: [copyBtn]).0)

        portField.stringValue = String(settings.port)
        portField.isEditable = true
        portField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        
        portStepper.minValue = 1024; portStepper.maxValue = 65535; portStepper.increment = 1
        portStepper.integerValue = settings.port
        portStepper.target = self; portStepper.action = #selector(portStepperChanged)
        
        applyPortBtn = NSButton(title: "Apply", target: self, action: #selector(applyPort))
        applyPortBtn.bezelStyle = .push
        
        serverVStack.addArrangedSubview(createRow(title: "Port", controls: [portField, portStepper, applyPortBtn]).0)
        hideLastSeparator(in: serverVStack)

        // STARTUP SECTION
        mainStack.addArrangedSubview(createSectionHeader("STARTUP"))
        let (startupCard, startupVStack) = createCard()
        mainStack.addArrangedSubview(startupCard)
        startupCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -60).isActive = true

        launchLoginSwitch.state = settings.launchAtLogin ? .on : .off
        launchLoginSwitch.target = self; launchLoginSwitch.action = #selector(launchLoginChanged)
        startupVStack.addArrangedSubview(createRow(title: "Launch at login", controls: [launchLoginSwitch]).0)

        autoStartSwitch.state = settings.autoStartServer ? .on : .off
        autoStartSwitch.target = self; autoStartSwitch.action = #selector(autoStartChanged)
        startupVStack.addArrangedSubview(createRow(title: "Start server automatically on launch", controls: [autoStartSwitch]).0)
        hideLastSeparator(in: startupVStack)

        // PLAYER SECTION
        mainStack.addArrangedSubview(createSectionHeader("PLAYER BEHAVIOR"))
        let (playerCard, pVStack) = createCard()
        self.playerVStack = pVStack // Save reference for dynamic updates
        mainStack.addArrangedSubview(playerCard)
        playerCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -60).isActive = true

        themePopup.addItems(withTitles: PlayerSelection.allCases.map { $0.displayName })
        let selIdx = PlayerSelection.allCases.firstIndex(of: currentSelection) ?? 0
        themePopup.selectItem(at: selIdx)
        themePopup.target = self; themePopup.action = #selector(themePickerChanged)
        themeRow = createRow(title: "Theme", controls: [themePopup]).0
        playerVStack.addArrangedSubview(themeRow)

        // Dynamic controls mapped to row containers
        skipPopup.addItems(withTitles: ["5 seconds", "10 seconds", "15 seconds", "30 seconds"])
        let skipMap = [5: 0, 10: 1, 15: 2, 30: 3]
        skipPopup.selectItem(at: skipMap[settings.skipInterval] ?? 2)
        skipPopup.target = self; skipPopup.action = #selector(skipChanged)
        skipRow = createRow(title: "Skip interval", controls: [skipPopup]).0
        playerVStack.addArrangedSubview(skipRow)

        volumeSwitch.state = settings.showVolumeControl ? .on : .off
        volumeSwitch.target = self; volumeSwitch.action = #selector(volumeChanged)
        volumeRow = createRow(title: "Show volume control", controls: [volumeSwitch]).0
        playerVStack.addArrangedSubview(volumeRow)

        lyricsSwitch.state = settings.showLyrics ? .on : .off
        lyricsSwitch.target = self; lyricsSwitch.action = #selector(lyricsChanged)
        lyricsRow = createRow(title: "Show lyrics", controls: [lyricsSwitch]).0
        playerVStack.addArrangedSubview(lyricsRow)

        lyricsAutoHideSwitch.state = settings.lyricsAutoHide ? .on : .off
        lyricsAutoHideSwitch.target = self; lyricsAutoHideSwitch.action = #selector(lyricsAutoHideChanged)
        lyricsAutoHideRow = createRow(title: "Auto-hide when no lyrics found", controls: [lyricsAutoHideSwitch]).0
        playerVStack.addArrangedSubview(lyricsAutoHideRow)

        importBtn = NSButton(title: "Import File…", target: self, action: #selector(importCustomFile))
        importBtn.bezelStyle = .push
        resetCustomBtn = NSButton(title: "Clear", target: self, action: #selector(resetCustomPlayer))
        resetCustomBtn.bezelStyle = .push
        customFileRow = createRow(title: "Active File", labelOverride: customFileLabel, controls: [importBtn, resetCustomBtn]).0
        playerVStack.addArrangedSubview(customFileRow)

        // Theme archive row
        importThemeBtn = NSButton(title: "Import .theme…", target: self, action: #selector(importThemeArchive))
        importThemeBtn.bezelStyle = .push
        removeThemeBtn = NSButton(title: "Remove", target: self, action: #selector(removeInstalledTheme))
        removeThemeBtn.bezelStyle = .push
        themeArchiveRow = createRow(title: "Installed", labelOverride: themeArchiveLabel, controls: [importThemeBtn, removeThemeBtn]).0
        playerVStack.addArrangedSubview(themeArchiveRow)

        // Security warning shown below the player card when theme archive is active
        themeWarningNote = NSTextField(wrappingLabelWithString:
            "⚠️  Only install themes from sources you trust. Theme archives run JavaScript in your browser and can control media playback.")
        themeWarningNote.font = .systemFont(ofSize: 11)
        themeWarningNote.textColor = .systemOrange
        themeWarningNote.isHidden = true
        themeWarningNote.translatesAutoresizingMaskIntoConstraints = false
        
        // FIX 3: Tell the text field its maximum layout width so it wraps text properly instead of expanding the window
        themeWarningNote.preferredMaxLayoutWidth = 440
        
        // Must be in hierarchy before activating cross-view constraints
        mainStack.addArrangedSubview(themeWarningNote)
        themeWarningNote.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -60).isActive = true

        // INFO FOOTER
        let footerNote = NSTextField(labelWithString: "Changes to port or volume control require restarting the server.")
        footerNote.font = .systemFont(ofSize: 11)
        footerNote.textColor = .tertiaryLabelColor
        footerNote.lineBreakMode = .byWordWrapping
        mainStack.addArrangedSubview(footerNote)
    }

    // MARK: - Auto Layout Helpers

    private func createSectionHeader(_ title: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = .systemFont(ofSize: 11, weight: .bold)
        lbl.textColor = .secondaryLabelColor
        return lbl
    }

    private func createCard() -> (NSView, NSStackView) {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.12).cgColor
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        card.layer?.borderWidth = 1
        card.setContentHuggingPriority(.required, for: .vertical) // Prevent card stretching

        let vStack = NSStackView()
        vStack.orientation = .vertical
        vStack.spacing = 0
        vStack.alignment = .width
        vStack.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            vStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
            vStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            vStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        return (card, vStack)
    }

    private func createRow(title: String, labelOverride: NSTextField? = nil, controls: [NSView]) -> (NSView, NSTextField) {
        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.spacing = 10
        rowStack.alignment = .centerY
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        rowStack.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rowStack.addArrangedSubview(spacer)

        if let override = labelOverride {
            override.textColor = .secondaryLabelColor
            rowStack.addArrangedSubview(override)
        }

        for ctrl in controls {
            rowStack.addArrangedSubview(ctrl)
        }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: container.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rowStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        let sep = NSBox()
        sep.identifier = NSUserInterfaceItemIdentifier("RowSeparator")
        sep.boxType = .custom
        sep.fillColor = NSColor.separatorColor.withAlphaComponent(0.2)
        sep.borderType = .noBorder
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sep)
        NSLayoutConstraint.activate([
            sep.heightAnchor.constraint(equalToConstant: 1),
            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return (container, titleLabel)
    }

    private func hideLastSeparator(in stack: NSStackView) {
        let visibleRows = stack.arrangedSubviews.filter { !$0.isHidden }
        for (index, row) in visibleRows.enumerated() {
            let isLast = (index == visibleRows.count - 1)
            if let separator = row.subviews.first(where: { $0.identifier?.rawValue == "RowSeparator" }) {
                separator.isHidden = isLast
            }
        }
    }

    // MARK: - Dynamic section & Auto-Shrinking Window

    private func updateDynamicSection() {
        let isCustomFile    = (currentSelection == .customHTML || currentSelection == .customJS)
        let isThemeArchive  = (currentSelection == .themeArchive)
        let isCustom        = isCustomFile || isThemeArchive
        let supportsLyr     = currentSelection.supportsLyrics

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
        let showLyr      = !isCustom && supportsLyr || isThemeArchive && supportsLyr
        let showAutoHide = showLyr && settings.showLyrics

        skipRow.isHidden           = !showSkip
        volumeRow.isHidden         = !showVol
        lyricsRow.isHidden         = !showLyr
        lyricsAutoHideRow.isHidden = !showAutoHide
        customFileRow.isHidden     = !isCustomFile
        themeArchiveRow.isHidden   = !isThemeArchive
        themeWarningNote.isHidden  = !isThemeArchive

        hideLastSeparator(in: playerVStack)

        if isCustomFile {
            if let name = fileName {
                customFileLabel.stringValue = name
                customFileLabel.textColor = .systemGreen
            } else {
                let ext = currentSelection == .customHTML ? "HTML" : "JS"
                customFileLabel.stringValue = "No \(ext) file imported"
                customFileLabel.textColor = .secondaryLabelColor
            }
            importBtn.title = currentSelection == .customHTML ? "Import HTML…" : "Import JS…"
            resetCustomBtn.isEnabled = fileName != nil
        }

        if isThemeArchive {
            let tm = ThemeArchiveManager.shared
            if let m = tm.manifest() {
                let byLine = m.author.map { " by \($0)" } ?? ""
                themeArchiveLabel.stringValue = "\(m.name)\(byLine)"
                themeArchiveLabel.textColor = .systemGreen
            } else {
                themeArchiveLabel.stringValue = "No theme installed"
                themeArchiveLabel.textColor = .secondaryLabelColor
            }
            removeThemeBtn.isEnabled = ThemeArchiveManager.shared.isInstalled
        }
        
        // 1. Force the stack view to update its internal calculations immediately
        mainStack.needsLayout = true
        mainStack.layoutSubtreeIfNeeded()
        
        // 2. Fetch the newly compressed fitting size
        let targetSize = mainStack.fittingSize
        
        // (Optional) Tell the parent view controller wrapper it should adopt this size
        self.preferredContentSize = targetSize
        
        // 3. Physically calculate the difference and animate the macOS window frame
        if let window = view.window {
            var newFrame = window.frame
            let currentContentRect = window.contentRect(forFrameRect: newFrame)
            
            // Calculate height difference (positive if shrinking, negative if growing)
            let heightDiff = currentContentRect.height - targetSize.height
            
            if abs(heightDiff) > 1 {
                // Adjust the origin.Y upward so the top-left corner stays pinned in place
                newFrame.origin.y += heightDiff
                newFrame.size.height -= heightDiff
                
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    context.allowsImplicitAnimation = true
                    
                    window.animator().setFrame(newFrame, display: true)
                    self.view.layoutSubtreeIfNeeded()
                }, completionHandler: nil)
            }
        } else {
            // Fallback for the very first load before a window exists
            view.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Server refresh

    private func refreshServer() {
        let running = httpServer.isRunning
        statusLabel.stringValue = running ? "● Running (Port \(httpServer.currentPort))" : "○ Stopped"
        statusLabel.textColor = running ? .systemGreen : .secondaryLabelColor

        if running, let ip = getLocalIP() {
            urlLabel.stringValue = "http://\(ip):\(httpServer.currentPort)"
        } else {
            urlLabel.stringValue = "Not available"
        }

        serverToggleBtn.title = running ? "Stop" : "Start"
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
            settings.useThemeArchive = false
            settings.customPlayerHTML = nil
            settings.customPlayerFileName = nil
            settings.customPlayerJS = nil
            settings.customPlayerJSFileName = nil
        case .themeArchive:
            settings.useThemeArchive = true
            settings.customPlayerHTML = nil
            settings.customPlayerFileName = nil
            settings.customPlayerJS = nil
            settings.customPlayerJSFileName = nil
        case .customHTML, .customJS:
            settings.useThemeArchive = false
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

    // MARK: - Theme archive actions

    @objc private func importThemeArchive() {
        // Security warning before opening the file picker
        let alert = NSAlert()
        alert.messageText = "Security Warning"
        alert.informativeText = """
            Theme archives contain JavaScript that runs in your browser and can control media playback.

            Only install themes from sources you trust. Do not install themes downloaded from unknown websites.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Import Anyway")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSOpenPanel()
        panel.title = "Select Theme Archive"
        panel.message = "Choose a .theme file to install"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.init(filenameExtension: "theme") ?? .zip]
        } else {
            panel.allowedFileTypes = ["theme", "zip"]
        }

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try ThemeArchiveManager.shared.installTheme(from: url)
                    DispatchQueue.main.async {
                        self.reloadThemePopup()
                        self.updateDynamicSection()
                    }
                } catch {
                    DispatchQueue.main.async {
                        let err = NSAlert()
                        err.messageText = "Could not install theme"
                        err.informativeText = error.localizedDescription
                        err.alertStyle = .critical
                        err.runModal()
                    }
                }
            }
        }
    }

    @objc private func removeInstalledTheme() {
        ThemeArchiveManager.shared.removeTheme()
        reloadThemePopup()
        updateDynamicSection()
    }

    private func reloadThemePopup() {
        let all = PlayerSelection.allCases
        themePopup.removeAllItems()
        themePopup.addItems(withTitles: all.map { $0.displayName })
        let idx = all.firstIndex(of: currentSelection) ?? 0
        themePopup.selectItem(at: idx)
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
