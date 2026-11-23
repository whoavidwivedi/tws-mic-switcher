import AppKit
import UserNotifications

public final class NotificationHelper: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationHelper()
    
    private override init() {
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            let center = UNUserNotificationCenter.current()
            center.delegate = self
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
    
    // Present notification banner even if the application is currently active
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.alert, .sound])
        }
    }
    
    public func sendNotification(
        title: String,
        subtitle: String,
        message: String,
        sound: String = "Pop"
    ) {
        guard ConfigManager.shared.config.notificationsEnabled else { return }
        
        DispatchQueue.main.async {
            // If running inside TWS Mic Switcher.app, use UNUserNotificationCenter / NSUserNotification
            if Bundle.main.bundleIdentifier != nil {
                let center = UNUserNotificationCenter.current()
                let content = UNMutableNotificationContent()
                content.title = title
                content.subtitle = subtitle
                content.body = message
                
                if sound.lowercased() == "pop" || sound.lowercased() == "default" || sound.isEmpty {
                    content.sound = UNNotificationSound.default
                } else {
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(sound + ".aiff"))
                }
                
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                
                center.add(request) { error in
                    if error != nil {
                        self.deliverViaNSUserNotification(title: title, subtitle: subtitle, message: message, sound: sound)
                    }
                }
            } else {
                // If triggered via raw terminal binary without bundle context,
                // launch the helper inside TWS Mic Switcher.app to display the genuine app notification
                let appPath = "/Users/whoavidwivedi/.gemini/antigravity/scratch/tws-mic-switcher/TWS Mic Switcher.app/Contents/MacOS/tws-mic-switcher"
                if FileManager.default.isExecutableFile(atPath: appPath) {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: appPath)
                    task.arguments = ["notify-dispatch", title, subtitle, message, sound]
                    try? task.run()
                } else {
                    self.deliverViaNSUserNotification(title: title, subtitle: subtitle, message: message, sound: sound)
                }
            }
        }
    }
    
    public func deliverViaNSUserNotification(title: String, subtitle: String, message: String, sound: String) {
        let notif = NSUserNotification()
        notif.title = title
        notif.subtitle = subtitle
        notif.informativeText = message
        notif.soundName = (sound.isEmpty || sound.lowercased() == "default") ? NSUserNotificationDefaultSoundName : sound
        NSUserNotificationCenter.default.deliver(notif)
    }
}
