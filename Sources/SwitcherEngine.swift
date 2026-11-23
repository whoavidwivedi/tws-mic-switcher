import Foundation
import CoreAudio

public final class SwitcherEngine {
    public static let shared = SwitcherEngine()
    
    private let workQueue = DispatchQueue(label: "com.twsmicswitcher.engine", qos: .userInitiated)
    private var verificationWorkItem: DispatchWorkItem?
    private var lastNotificationTime: Date = Date.distantPast
    private var lastHandledBluetoothID: AudioObjectID = 0
    
    private init() {}
    
    public func start() {
        log("TWS Mic Switcher engine starting up...")
        
        // Initial evaluation on startup
        workQueue.async { [weak self] in
            self?.evaluateAndSwitch(reason: "Engine Startup")
        }
        
        // Register CoreAudio listeners
        CoreAudioService.shared.addAudioListeners(queue: workQueue) { [weak self] eventName in
            self?.handleAudioChangeEvent(eventName: eventName)
        }
        
        log("CoreAudio listeners active. Watching for TWS / Bluetooth audio connections.")
    }
    
    private func handleAudioChangeEvent(eventName: String) {
        // Immediate check
        evaluateAndSwitch(reason: "Event: \(eventName)")
        
        // Scheduled follow-up check to catch macOS delayed audio routing
        verificationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluateAndSwitch(reason: "Delayed Verification (\(eventName))")
        }
        verificationWorkItem = item
        workQueue.asyncAfter(deadline: .now() + 0.45, execute: item)
    }
    
    public func evaluateAndSwitch(reason: String) {
        guard ConfigManager.shared.config.enabled else {
            return
        }
        
        guard let currentInput = CoreAudioService.shared.getDefaultInputDevice() else {
            return
        }
        
        // If current input is Bluetooth, we must switch it back to Built-In Mic
        if currentInput.isBluetooth {
            guard let targetMic = CoreAudioService.shared.findBuiltInMicrophone(
                preferredUID: ConfigManager.shared.config.preferredInputUID
            ) else {
                log("⚠️ Bluetooth input detected ('\(currentInput.name)'), but no suitable built-in microphone was found.")
                return
            }
            
            if targetMic.id == currentInput.id {
                // Already target
                return
            }
            
            log("⚡️ [\(reason)] Bluetooth input active: '\(currentInput.name)'. Switching default input to '\(targetMic.name)'...")
            
            let success = CoreAudioService.shared.setDefaultInputDevice(id: targetMic.id)
            if success {
                let currentOutput = CoreAudioService.shared.getDefaultOutputDevice()
                log("✅ Successfully switched microphone to '\(targetMic.name)'. Output remains on '\(currentOutput?.name ?? "Unknown")'.")
                
                // Rate-limit notifications to once every 3 seconds per device transition
                let now = Date()
                if now.timeIntervalSince(lastNotificationTime) > 3.0 || lastHandledBluetoothID != currentInput.id {
                    lastNotificationTime = now
                    lastHandledBluetoothID = currentInput.id
                    
                    let outName = currentOutput?.name ?? "Earbuds"
                    let inName = targetMic.name
                    
                    NotificationHelper.shared.sendNotification(
                        title: "🎧 \(currentInput.name) Connected",
                        subtitle: "🎙️ Mic Kept on \(inName)",
                        message: "✨ Studio-grade mic active • HD Stereo preserved on \(outName)",
                        sound: "Pop"
                    )
                }
            } else {
                log("❌ Failed to set default input device to ID \(targetMic.id).")
            }
        }
    }
    
    public func forceSwitchToBuiltIn() -> (success: Bool, message: String) {
        guard let targetMic = CoreAudioService.shared.findBuiltInMicrophone(
            preferredUID: ConfigManager.shared.config.preferredInputUID
        ) else {
            return (false, "No suitable built-in microphone found.")
        }
        
        let success = CoreAudioService.shared.setDefaultInputDevice(id: targetMic.id)
        if success {
            return (true, "Switched default input to '\(targetMic.name)'.")
        } else {
            return (false, "CoreAudio failed to set default input.")
        }
    }
    
    public func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)"
        
        print(formatted)
        fflush(stdout)
    }
}
