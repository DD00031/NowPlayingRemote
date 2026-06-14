import Foundation
import ServiceManagement

final class SettingsManager {

    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case port               = "serverPort"
        case autoStartServer    = "autoStartServer"
        case skipInterval       = "skipInterval"
        case showVolumeControl  = "showVolumeControl"
        case showLikeButton     = "showLikeButton"
        case launchAtLogin      = "launchAtLogin"
        case showLyrics         = "showLyrics"
    }

    private init() {}

    var port: Int {
        get { let v = defaults.integer(forKey: Key.port.rawValue); return v > 0 ? v : 8080 }
        set { defaults.set(newValue, forKey: Key.port.rawValue) }
    }

    var autoStartServer: Bool {
        get { defaults.object(forKey: Key.autoStartServer.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoStartServer.rawValue) }
    }

    var skipInterval: Int {
        get { let v = defaults.integer(forKey: Key.skipInterval.rawValue); return v > 0 ? v : 15 }
        set { defaults.set(newValue, forKey: Key.skipInterval.rawValue) }
    }

    var showVolumeControl: Bool {
        get { defaults.object(forKey: Key.showVolumeControl.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showVolumeControl.rawValue) }
    }

    var showLikeButton: Bool {
        get { defaults.object(forKey: Key.showLikeButton.rawValue) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.showLikeButton.rawValue) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin.rawValue) }
        set {
            defaults.set(newValue, forKey: Key.launchAtLogin.rawValue)
            applyLaunchAtLogin(newValue)
        }
    }

    var showLyrics: Bool {
        get { defaults.object(forKey: Key.showLyrics.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showLyrics.rawValue) }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled { try service.register() }
                else        { try service.unregister() }
            } catch {
                // Registration can fail if the user hasn't granted permission
            }
        }
    }
}
