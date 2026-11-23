import Foundation
import CoreAudio

public final class SwitcherEngine {
    public static let shared = SwitcherEngine()
    
    private let workQueue = DispatchQueue(label: "com.twsmicswitcher.engine", qos: .userInitiated)
    private var verificationWorkItem: DispatchWorkItem?
    
    // Tracking connected Bluetooth devices to distinguish new connections from manual changes
    private var knownBluetoothDeviceIDs: Set<AudioObjectID> = []
    private var connectionWindowDeviceID: AudioObjectID? = nil
    private var connectionWindowExpires: Date = Date.distantPast
    private var lastLoggedManualID: AudioObjectID = 0
    
    private init() {}
    
    public func start() {
        log("TWS Mic Switcher engine v1.1.0 starting up (Silent & Non-Intrusive Mode)...")
        
        // Initial inventory of currently connected Bluetooth devices
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let initialBT = CoreAudioService.shared.getAllDevices().filter { $0.isBluetooth }
            self.knownBluetoothDeviceIDs = Set(initialBT.map { $0.id })
            self.log("Initial state: \(initialBT.count) Bluetooth audio device(s) detected.")
        }
        
        // Register CoreAudio property listeners
        CoreAudioService.shared.addAudioListeners(queue: workQueue) { [weak self] eventName in
            self?.handleAudioChangeEvent(eventName: eventName)
        }
        
        log("CoreAudio listeners active. Watching for TWS / Bluetooth connection events.")
    }
    
    private func handleAudioChangeEvent(eventName: String) {
        if eventName == "DevicesList" {
            // Check for newly connected or disconnected Bluetooth devices
            let currentBT = CoreAudioService.shared.getAllDevices().filter { $0.isBluetooth }
            let currentIDs = Set(currentBT.map { $0.id })
            
            // Find devices that were NOT in knownBluetoothDeviceIDs
            let newlyConnected = currentBT.filter { !knownBluetoothDeviceIDs.contains($0.id) }
            if let newDevice = newlyConnected.first {
                log("🎧 TWS connection event: '\(newDevice.name)' (ID: \(newDevice.id)) connected. Opening auto-switch window.")
                connectionWindowDeviceID = newDevice.id
                connectionWindowExpires = Date().addingTimeInterval(4.0) // 4-second connection window for macOS routing
            }
            
            knownBluetoothDeviceIDs = currentIDs
        }
        
        // Immediate check
        evaluateAndSwitch(reason: "Event: \(eventName)")
        
        // Scheduled follow-up check to catch macOS delayed audio routing during initial connection
        if Date() < connectionWindowExpires {
            verificationWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.evaluateAndSwitch(reason: "Delayed Connection Verification (\(eventName))")
            }
            verificationWorkItem = item
            workQueue.asyncAfter(deadline: .now() + 0.45, execute: item)
        }
    }
    
    public func evaluateAndSwitch(reason: String) {
        guard ConfigManager.shared.config.enabled else {
            return
        }
        
        guard let currentInput = CoreAudioService.shared.getDefaultInputDevice() else {
            return
        }
        
        // If current input is Bluetooth, determine whether it's an initial connection or a manual user choice
        if currentInput.isBluetooth {
            let isConnectionEvent = (currentInput.id == connectionWindowDeviceID && Date() <= connectionWindowExpires)
            
            if isConnectionEvent {
                // Initial TWS connection event: Revert mic back to MacBook built-in mic
                guard let targetMic = CoreAudioService.shared.findBuiltInMicrophone(
                    preferredUID: ConfigManager.shared.config.preferredInputUID
                ) else {
                    log("⚠️ Bluetooth input active ('\(currentInput.name)'), but no suitable built-in microphone was found.")
                    return
                }
                
                if targetMic.id == currentInput.id {
                    return
                }
                
                log("⚡️ [\(reason)] Newly connected TWS detected ('\(currentInput.name)'). Auto-switching mic to '\(targetMic.name)' to protect HD stereo output.")
                
                let success = CoreAudioService.shared.setDefaultInputDevice(id: targetMic.id)
                if success {
                    let currentOutput = CoreAudioService.shared.getDefaultOutputDevice()
                    log("✅ Default input set to '\(targetMic.name)'. Output remains on '\(currentOutput?.name ?? "Unknown")'.")
                    // Window served its purpose for this connection
                    connectionWindowDeviceID = nil
                    connectionWindowExpires = Date.distantPast
                } else {
                    log("❌ Failed to set default input device to ID \(targetMic.id).")
                }
            } else {
                // Manual User Change!
                // The device was already connected and outside the initial connection window.
                // The user deliberately selected this microphone in Control Center / System Settings.
                if lastLoggedManualID != currentInput.id {
                    lastLoggedManualID = currentInput.id
                    log("ℹ️ Manual mic selection: '\(currentInput.name)'. Respecting user choice (will not revert).")
                }
            }
        } else {
            // Input is not Bluetooth (e.g. built-in mic or USB mic)
            lastLoggedManualID = 0
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
