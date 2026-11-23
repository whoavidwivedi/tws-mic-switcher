import Foundation

public struct AppConfig: Codable {
    public var enabled: Bool
    public var notificationsEnabled: Bool
    public var preferredInputUID: String
    public var allowUSBInputs: Bool
    
    public static let `default` = AppConfig(
        enabled: true,
        notificationsEnabled: false,
        preferredInputUID: "",
        allowUSBInputs: true
    )
}

public final class ConfigManager {
    public static let shared = ConfigManager()
    
    private let configURL: URL
    public private(set) var config: AppConfig
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/tws-mic-switcher", isDirectory: true)
        self.configURL = dir.appendingPathComponent("config.json")
        
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        if let data = try? Data(contentsOf: configURL),
           let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) {
            self.config = loaded
        } else {
            self.config = AppConfig.default
            self.save()
        }
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL)
        }
    }
    
    public func setEnabled(_ value: Bool) {
        config.enabled = value
        save()
    }
    
    public func setNotificationsEnabled(_ value: Bool) {
        config.notificationsEnabled = value
        save()
    }
    
    public func setPreferredInputUID(_ uid: String) {
        config.preferredInputUID = uid
        save()
    }
}
