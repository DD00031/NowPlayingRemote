import AppKit
import CoreImage

final class QRCodeWindowController {

    private var panel: NSPanel?

    func show(url: String, relativeTo button: NSStatusBarButton?) {
        if let existing = panel, existing.isVisible {
            existing.close()
            panel = nil
            return
        }

        guard let qr = generateQRCode(from: url) else { return }

        let padding: CGFloat = 24
        let imgSize: CGFloat = 220
        let totalW = imgSize + padding * 2
        let totalH = imgSize + padding * 2 + 44 // extra for label

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: totalW, height: totalH),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "Scan to Connect"
        p.isFloatingPanel = true
        p.level = .floating
        p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false

        let container = NSView(frame: p.contentView!.bounds)
        container.autoresizingMask = [.width, .height]
        p.contentView!.addSubview(container)

        // QR image
        let imgView = NSImageView(frame: NSRect(x: padding, y: padding + 36, width: imgSize, height: imgSize))
        imgView.image = qr
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.wantsLayer = true
        imgView.layer?.cornerRadius = 10
        imgView.layer?.masksToBounds = true
        container.addSubview(imgView)

        // URL label
        let label = NSTextField(labelWithString: url)
        label.frame = NSRect(x: padding, y: 10, width: imgSize, height: 22)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.isSelectable = true
        container.addSubview(label)

        // Position below the status bar button if possible
        if let btn = button, let btnWindow = btn.window {
            let btnRect = btnWindow.convertToScreen(btn.convert(btn.bounds, to: nil))
            let x = btnRect.midX - totalW / 2
            let y = btnRect.minY - totalH - 4
            p.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            p.center()
        }

        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    private func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let raw = filter.outputImage else { return nil }

        let scale = 220.0 / raw.extent.width
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Invert colours for dark/light mode compatibility — keep it black on white
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
