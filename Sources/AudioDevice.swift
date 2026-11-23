import Foundation
import CoreAudio

public struct AudioDevice: CustomStringConvertible {
    public let id: AudioObjectID
    public let name: String
    public let uid: String
    public let transportType: UInt32
    public let hasInput: Bool
    public let hasOutput: Bool
    
    public var isBluetooth: Bool {
        if transportType == kAudioDeviceTransportTypeBluetooth ||
           transportType == kAudioDeviceTransportTypeBluetoothLE {
            return true
        }
        // Fallback for Bluetooth devices reporting custom/zero transport:
        // MAC-address-like UID pattern (e.g., "74-45-ce-..." or "aa:bb:cc:...")
        let lowerUID = uid.lowercased()
        let hasMacDashes = lowerUID.split(separator: "-").count >= 6
        let hasMacColons = lowerUID.split(separator: ":").count >= 6
        if hasMacDashes || hasMacColons {
            return true
        }
        return false
    }
    
    public var isBuiltIn: Bool {
        if transportType == kAudioDeviceTransportTypeBuiltIn {
            return true
        }
        let lowerUID = uid.lowercased()
        let lowerName = name.lowercased()
        if lowerUID.contains("builtin") || lowerUID.contains("built-in") {
            return true
        }
        if lowerName.contains("built-in") || lowerName.contains("macbook") || lowerName.contains("internal microphone") {
            return true
        }
        return false
    }
    
    public var isUSB: Bool {
        return transportType == kAudioDeviceTransportTypeUSB
    }
    
    public var transportName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return "Built-In"
        case kAudioDeviceTransportTypeBluetooth:
            return "Bluetooth (Classic)"
        case kAudioDeviceTransportTypeBluetoothLE:
            return "Bluetooth LE"
        case kAudioDeviceTransportTypeUSB:
            return "USB"
        case kAudioDeviceTransportTypeDisplayPort:
            return "DisplayPort"
        case kAudioDeviceTransportTypeHDMI:
            return "HDMI"
        case kAudioDeviceTransportTypeVirtual:
            return "Virtual"
        default:
            if isBluetooth { return "Bluetooth (Detected by UID)" }
            if isBuiltIn { return "Built-In (Detected by Name)" }
            return "Other (\(transportType))"
        }
    }
    
    public var description: String {
        let streams = [hasInput ? "Input" : nil, hasOutput ? "Output" : nil].compactMap { $0 }.joined(separator: "/")
        return "[\(id)] \"\(name)\" (\(transportName), \(streams.isEmpty ? "None" : streams), UID: \(uid))"
    }
}
