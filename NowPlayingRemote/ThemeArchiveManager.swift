import Foundation

// MARK: - Theme Manifest

/// Decoded from theme.json inside a .theme archive.
struct ThemeManifest: Codable {
    let name: String
    let author: String?
    let version: String?
    let description: String?
    /// Set true in theme.json to show a Lyrics button and receive lyricsVersion updates.
    let supportsLyrics: Bool?
}

// MARK: - Import errors

enum ThemeImportError: LocalizedError {
    case invalidArchive
    case missingManifest
    case missingCSS
    case invalidManifest(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:            return "The file is not a valid .theme archive (must be a ZIP)."
        case .missingManifest:           return "Missing required file: theme.json"
        case .missingCSS:                return "Missing required file: styles.css"
        case .invalidManifest(let msg):  return "Invalid theme.json — \(msg)"
        case .extractionFailed(let msg): return "Could not extract archive: \(msg)"
        }
    }
}

// MARK: - Manager

/// Handles install, removal, and asset serving for .theme archives.
///
/// A .theme file is a ZIP renamed with the .theme extension. Required layout:
///   theme.json   — metadata (name, author, version, supportsLyrics)
///   styles.css   — CSS injected into the base HTML template
/// Optional:
///   script.js    — JS injected after the default onStateUpdate handler
///   assets/      — Images, fonts, SVGs served at /theme-assets/<filename>
///
/// All content lives under Application Support/NowPlayingRemote/ImportedTheme/.
/// Only one theme can be installed at a time; importing replaces the previous one.
final class ThemeArchiveManager {

    static let shared = ThemeArchiveManager()
    private let fm = FileManager.default

    // MARK: Paths

    var installDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NowPlayingRemote/ImportedTheme", isDirectory: true)
    }

    var isInstalled: Bool {
        fm.fileExists(atPath: installDir.appendingPathComponent("theme.json").path)
    }

    // MARK: Read helpers

    func manifest() -> ThemeManifest? {
        guard let data = try? Data(contentsOf: installDir.appendingPathComponent("theme.json")) else { return nil }
        return try? JSONDecoder().decode(ThemeManifest.self, from: data)
    }

    func css() -> String? {
        try? String(contentsOf: installDir.appendingPathComponent("styles.css"), encoding: .utf8)
    }

    func js() -> String? {
        try? String(contentsOf: installDir.appendingPathComponent("script.js"), encoding: .utf8)
    }

    /// Data for a file in the assets/ subfolder.
    func assetData(name: String) -> Data? {
        // Reject path traversal attempts
        guard !name.contains(".."), !name.hasPrefix("/") else { return nil }
        return try? Data(contentsOf: installDir.appendingPathComponent("assets/\(name)"))
    }

    func mimeType(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "svg":         return "image/svg+xml"
        case "webp":        return "image/webp"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        default:            return "application/octet-stream"
        }
    }

    // MARK: Install

    /// Validates and installs a .theme archive. Throws `ThemeImportError` on failure.
    /// This is synchronous and may block briefly on large archives — call off main thread.
    func installTheme(from sourceURL: URL) throws {
        // Extract to a temp directory
        let tempDir = fm.temporaryDirectory.appendingPathComponent("NPR-theme-\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-q", "-o", sourceURL.path, "-d", tempDir.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()   // suppress stdout

        do { try proc.run() } catch {
            throw ThemeImportError.invalidArchive
        }
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? "unknown error"
            throw ThemeImportError.extractionFailed(msg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // theme.json may be in a top-level subfolder (e.g. MyTheme/theme.json) — locate it
        guard let manifestURL = findFile(named: "theme.json", in: tempDir) else {
            throw ThemeImportError.missingManifest
        }
        let themeRoot = manifestURL.deletingLastPathComponent()

        // Validate manifest
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ThemeManifest.self, from: data) else {
            throw ThemeImportError.invalidManifest("Could not parse theme.json as JSON")
        }
        guard !manifest.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ThemeImportError.invalidManifest("'name' field must not be empty")
        }

        // styles.css is mandatory
        guard fm.fileExists(atPath: themeRoot.appendingPathComponent("styles.css").path) else {
            throw ThemeImportError.missingCSS
        }

        // Atomic install: remove old theme, copy new one
        try? fm.removeItem(at: installDir)
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)

        let items = (try? fm.contentsOfDirectory(at: themeRoot, includingPropertiesForKeys: nil)) ?? []
        for item in items {
            try fm.copyItem(at: item, to: installDir.appendingPathComponent(item.lastPathComponent))
        }
    }

    // MARK: Remove

    func removeTheme() {
        try? fm.removeItem(at: installDir)
    }

    // MARK: Private

    private func findFile(named name: String, in directory: URL) -> URL? {
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: []) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return url
        }
        return nil
    }
}
