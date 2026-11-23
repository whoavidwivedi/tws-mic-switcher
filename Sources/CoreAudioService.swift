import Foundation
import CoreAudio

public final class CoreAudioService {
    public static let shared = CoreAudioService()
    
    private init() {}
    
    // MARK: - Property Getters
    
    public func getStringProperty(id: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfStr: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, &cfStr)
        guard status == noErr, let val = cfStr?.takeRetainedValue() else { return nil }
        return val as String
    }
    
    public func getUInt32Property(id: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &dataSize, &value)
        guard status == noErr else { return nil }
        return value
    }
    
    public func hasStreams(id: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }
    
    public func getDevice(id: AudioObjectID) -> AudioDevice? {
        guard let name = getStringProperty(id: id, selector: kAudioObjectPropertyName) else { return nil }
        let uid = getStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID) ?? ""
        let transport = getUInt32Property(id: id, selector: kAudioDevicePropertyTransportType) ?? 0
        let hasIn = hasStreams(id: id, scope: kAudioDevicePropertyScopeInput)
        let hasOut = hasStreams(id: id, scope: kAudioDevicePropertyScopeOutput)
        return AudioDevice(id: id, name: name, uid: uid, transportType: transport, hasInput: hasIn, hasOutput: hasOut)
    }
    
    public func getAllDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }
        
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids)
        guard status == noErr else { return [] }
        return ids
    }
    
    public func getAllDevices() -> [AudioDevice] {
        return getAllDeviceIDs().compactMap { getDevice(id: $0) }
    }
    
    // MARK: - Defaults
    
    public func getDefaultInputDevice() -> AudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr, deviceID != 0, deviceID != kAudioObjectUnknown else { return nil }
        return getDevice(id: deviceID)
    }
    
    public func getDefaultOutputDevice() -> AudioDevice? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID)
        guard status == noErr, deviceID != 0, deviceID != kAudioObjectUnknown else { return nil }
        return getDevice(id: deviceID)
    }
    
    // MARK: - Safe Input Device Switching
    // SAFETY GUARANTEE: This service ONLY modifies kAudioHardwarePropertyDefaultInputDevice.
    // Audio output (kAudioHardwarePropertyDefaultOutputDevice), output volume, mute,
    // and streams are strictly READ-ONLY and will NEVER be altered.
    public func setDefaultInputDevice(id: AudioObjectID) -> Bool {
        // Critical safety check: Ensure the target device actually has input channels
        guard hasStreams(id: id, scope: kAudioDevicePropertyScopeInput) else {
            print("🛑 Safety Block: Device ID \(id) has no input streams. Refusing to set as input.")
            return false
        }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var targetID = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &targetID
        )
        return status == noErr
    }
    
    // MARK: - Microphone Detection
    
    public func findBuiltInMicrophone(preferredUID: String? = nil) -> AudioDevice? {
        let devices = getAllDevices()
        
        // 1. If preferred UID specified, check if that device is connected
        if let preferred = preferredUID, !preferred.isEmpty {
            if let matched = devices.first(where: { $0.uid == preferred && $0.hasInput }) {
                return matched
            }
        }
        
        // 2. Hardware built-in with input stream
        if let builtIn = devices.first(where: { $0.isBuiltIn && $0.hasInput }) {
            return builtIn
        }
        
        // 3. Name heuristics
        let nameKeywords = ["built-in", "macbook", "internal", "mac audio"]
        for kw in nameKeywords {
            if let matched = devices.first(where: { $0.hasInput && $0.name.localizedCaseInsensitiveContains(kw) }) {
                return matched
            }
        }
        
        // 4. Fallback: Any non-Bluetooth input device
        if let nonBT = devices.first(where: { $0.hasInput && !$0.isBluetooth }) {
            return nonBT
        }
        
        return nil
    }
    
    // MARK: - Property Listeners
    
    public func addAudioListeners(queue: DispatchQueue, onChange: @escaping (String) -> Void) {
        let selectors: [(AudioObjectPropertySelector, String)] = [
            (kAudioHardwarePropertyDefaultInputDevice, "DefaultInputDevice"),
            (kAudioHardwarePropertyDefaultOutputDevice, "DefaultOutputDevice"),
            (kAudioHardwarePropertyDevices, "DevicesList")
        ]
        
        for (selector, name) in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue
            ) { _, _ in
                onChange(name)
            }
            
            if status != noErr {
                print("Warning: Failed to add CoreAudio listener for \(name) (status: \(status))")
            }
        }
    }
}
