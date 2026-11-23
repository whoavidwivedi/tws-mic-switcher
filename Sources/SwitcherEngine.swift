import Foundation
import CoreAudio

public final class SwitcherEngine {
    public static let shared = SwitcherEngine()
    
    private let workQueue = DispatchQueue(label: "com.twsmicswitcher.engine", qos: .userInitiated)
    private var verificationWorkItem: DispatchWorkItem?
    
    // Tracking connected Bluetooth devices to distinguish initial connections from manual changes
    private var knownBluetoothDeviceIDs: Set<AudioObjectID> = []
    private var connectionWindowDeviceID: AudioObjectID? = nil
    private var connectionWindowExpires: Date = Date.distantPast
    private var lastLoggedManualID: AudioObjectID = 0
    
    private init() {}
    
    public func start() {
        log("tws-mic-switcher daemon started (pid: \(ProcessInfo.processInfo.processIdentifier))")
        
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let initialBT = CoreAudioService.shared.getAllDevices().filter { $0.isBluetooth }
            self.knownBluetoothDeviceIDs = Set(initialBT.map { $0.id })
            self.log("Discovered \(initialBT.count) connected Bluetooth audio device(s)")
        }
        
        CoreAudioService.shared.addAudioListeners(queue: workQueue) { [weak self] eventName in
            self?.handleAudioChangeEvent(eventName: eventName)
        }
    }
    
    private func handleAudioChangeEvent(eventName: String) {
        if eventName == "DevicesList" {
            let currentBT = CoreAudioService.shared.getAllDevices().filter { $0.isBluetooth }
            let currentIDs = Set(currentBT.map { $0.id })
            
            let newlyConnected = currentBT.filter { !knownBluetoothDeviceIDs.contains($0.id) }
            if let newDevice = newlyConnected.first {
                log("Bluetooth device connected: '\(newDevice.name)' (id: \(newDevice.id)). Connection window open (4s).")
                connectionWindowDeviceID = newDevice.id
                connectionWindowExpires = Date().addingTimeInterval(4.0)
            }
            
            knownBluetoothDeviceIDs = currentIDs
        }
        
        evaluateAndSwitch(reason: eventName)
        
        if Date() < connectionWindowExpires {
            verificationWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.evaluateAndSwitch(reason: "delayed-verification")
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
        
        if currentInput.isBluetooth {
            let isConnectionEvent = (currentInput.id == connectionWindowDeviceID && Date() <= connectionWindowExpires)
            
            if isConnectionEvent {
                guard let targetMic = CoreAudioService.shared.findBuiltInMicrophone(
                    preferredUID: ConfigManager.shared.config.preferredInputUID
                ) else {
                    log("Warning: Bluetooth input active ('\(currentInput.name)'), but built-in microphone not found.")
                    return
                }
                
                if targetMic.id == currentInput.id {
                    return
                }
                
                log("Initial connection routing: setting default input to '\(targetMic.name)' (preserving stereo output on '\(currentInput.name)')")
                
                let success = CoreAudioService.shared.setDefaultInputDevice(id: targetMic.id)
                if success {
                    let currentOutput = CoreAudioService.shared.getDefaultOutputDevice()
                    log("Default input switched to '\(targetMic.name)' (output: '\(currentOutput?.name ?? "unknown")')")
                    connectionWindowDeviceID = nil
                    connectionWindowExpires = Date.distantPast
                } else {
                    log("Error: Failed to set default input device to id \(targetMic.id)")
                }
            } else {
                // Manual user change: outside connection window, retain user preference
                if lastLoggedManualID != currentInput.id {
                    lastLoggedManualID = currentInput.id
                    log("Manual input selection: '\(currentInput.name)'. Retaining user choice.")
                }
            }
        } else {
            lastLoggedManualID = 0
        }
    }
    
    public func forceSwitchToBuiltIn() -> (success: Bool, message: String) {
        guard let targetMic = CoreAudioService.shared.findBuiltInMicrophone(
            preferredUID: ConfigManager.shared.config.preferredInputUID
        ) else {
            return (false, "Built-in microphone not found.")
        }
        
        let success = CoreAudioService.shared.setDefaultInputDevice(id: targetMic.id)
        if success {
            return (true, "Switched default input to '\(targetMic.name)'.")
        } else {
            return (false, "Failed to set default input device.")
        }
    }
    
    public func log(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)"
        
        print(formatted)
        fflush(stdout)
    }
}
