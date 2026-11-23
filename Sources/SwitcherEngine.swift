import Foundation
import CoreAudio
import IOKit
import IOKit.pwr_mgt

public final class SwitcherEngine {
    public static let shared = SwitcherEngine()

    private let workQueue = DispatchQueue(label: "com.twsmicswitcher.engine", qos: .userInitiated)
    private var verificationWorkItems: [DispatchWorkItem] = []

    // Devices already present when we last observed the audio topology.
    private var knownBluetoothDeviceIDs: Set<AudioObjectID> = []

    // Devices that are allowed to be auto-switched right now. A window is opened
    // for newly connected devices, at daemon startup, and after system wake.
    private var connectionWindowDeviceIDs: Set<AudioObjectID> = []
    private var connectionWindowExpires: Date = .distantPast

    // A Bluetooth input explicitly chosen by the user. Retained until the device
    // disconnects, reconnects, or the user forces a switch.
    private var manualOverrideDeviceID: AudioObjectID? = nil
    private var lastLoggedManualID: AudioObjectID = 0

    // IOKit system power notifications (sleep / wake).
    private var powerConnection: io_connect_t = 0
    private var powerNotifier: io_object_t = 0
    private var powerNotifyPort: IONotificationPortRef?

    private init() {}

    public func start() {
        log("tws-mic-switcher daemon started (v\(appVersion), pid: \(ProcessInfo.processInfo.processIdentifier))")

        workQueue.async { [weak self] in
            self?.prepareInitialState()
        }

        CoreAudioService.shared.addAudioListeners(queue: workQueue) { [weak self] eventName in
            self?.handleAudioChangeEvent(eventName: eventName)
        }

        startPowerMonitoring()
    }

    private func prepareInitialState() {
        let initialBT = CoreAudioService.shared.getAllDevices().filter { $0.isBluetooth }
        knownBluetoothDeviceIDs = Set(initialBT.map { $0.id })
        log("Discovered \(initialBT.count) connected Bluetooth audio device(s)")

        // Devices that were already connected at login are never "new" to us.
        // Open a startup window so the current routing is eligible for switching.
        var eligibleIDs = Set(initialBT.map { $0.id })
        if let input = CoreAudioService.shared.getDefaultInputDevice(), input.isBluetooth {
            eligibleIDs.insert(input.id)
            log("Startup: Bluetooth input '\(input.name)' is active. Routing to built-in microphone.")
        }

        if !eligibleIDs.isEmpty {
            openConnectionWindow(deviceIDs: eligibleIDs, seconds: 10)
            scheduleVerifications(in: [1.0, 3.0, 6.0])
        }

        evaluateAndSwitch(reason: "startup")
    }

    private func handleAudioChangeEvent(eventName: String) {
        if eventName == "DevicesList" {
            let currentBT = CoreAudioService.shared.getAllDevices().filter { $0.isBluetooth }
            let currentIDs = Set(currentBT.map { $0.id })
            let newlyConnected = currentBT.filter { !knownBluetoothDeviceIDs.contains($0.id) }

            if !newlyConnected.isEmpty {
                let names = newlyConnected.map { "'\($0.name)'" }.joined(separator: ", ")
                log("Bluetooth device connected: \(names). Connection window open.")
                openConnectionWindow(deviceIDs: Set(newlyConnected.map { $0.id }), seconds: 8)
                manualOverrideDeviceID = nil
                lastLoggedManualID = 0
                scheduleVerifications(in: [0.5, 2.0, 5.0])
            }

            if let override = manualOverrideDeviceID, !currentIDs.contains(override) {
                manualOverrideDeviceID = nil
            }

            knownBluetoothDeviceIDs = currentIDs
        }

        evaluateAndSwitch(reason: eventName)

        if Date() < connectionWindowExpires {
            scheduleVerifications(in: [0.5, 2.0])
        }
    }

    public func evaluateAndSwitch(reason: String) {
        guard ConfigManager.shared.config.enabled else {
            return
        }

        guard let currentInput = CoreAudioService.shared.getDefaultInputDevice() else {
            return
        }

        guard currentInput.isBluetooth else {
            manualOverrideDeviceID = nil
            lastLoggedManualID = 0
            return
        }

        if manualOverrideDeviceID == currentInput.id {
            logManualSelectionIfNeeded(currentInput)
            return
        }

        let isConnectionEvent = Date() <= connectionWindowExpires &&
            connectionWindowDeviceIDs.contains(currentInput.id)

        guard isConnectionEvent else {
            // A Bluetooth input selected outside a connection/startup/wake window
            // is treated as a deliberate user choice.
            manualOverrideDeviceID = currentInput.id
            logManualSelectionIfNeeded(currentInput)
            return
        }

        guard let targetMic = CoreAudioService.shared.findBuiltInMicrophone(
            preferredUID: ConfigManager.shared.config.preferredInputUID
        ) else {
            log("Warning: Bluetooth input active ('\(currentInput.name)'), but built-in microphone not found.")
            return
        }

        if targetMic.id == currentInput.id {
            return
        }

        log("Auto-routing input to '\(targetMic.name)' (reason: \(reason), preserving stereo output on '\(currentInput.name)')")

        let success = CoreAudioService.shared.setDefaultInputDevice(id: targetMic.id)
        if success {
            let currentOutput = CoreAudioService.shared.getDefaultOutputDevice()
            log("Default input switched to '\(targetMic.name)' (output: '\(currentOutput?.name ?? "unknown")')")
            clearConnectionWindow()
            manualOverrideDeviceID = nil
            lastLoggedManualID = 0
        } else {
            log("Error: Failed to set default input device to id \(targetMic.id)")
        }
    }

    public func forceSwitchToBuiltIn() -> (success: Bool, message: String) {
        clearConnectionWindow()
        manualOverrideDeviceID = nil
        lastLoggedManualID = 0

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

    // MARK: - Connection windows

    private func openConnectionWindow(deviceIDs: Set<AudioObjectID>, seconds: TimeInterval) {
        if Date() < connectionWindowExpires {
            connectionWindowDeviceIDs.formUnion(deviceIDs)
        } else {
            connectionWindowDeviceIDs = deviceIDs
        }
        connectionWindowExpires = Date().addingTimeInterval(seconds)
    }

    private func clearConnectionWindow() {
        connectionWindowDeviceIDs.removeAll()
        connectionWindowExpires = .distantPast
    }

    private func scheduleVerifications(in delays: [TimeInterval]) {
        for item in verificationWorkItems {
            item.cancel()
        }

        verificationWorkItems = delays.map { delay in
            let item = DispatchWorkItem { [weak self] in
                self?.evaluateAndSwitch(reason: "delayed-verification")
            }
            workQueue.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
    }

    private func logManualSelectionIfNeeded(_ device: AudioDevice) {
        guard lastLoggedManualID != device.id else {
            return
        }
        lastLoggedManualID = device.id
        log("Manual input selection: '\(device.name)'. Retaining user choice.")
    }

    // MARK: - Wake handling

    private func startPowerMonitoring() {
        let thread = Thread { [weak self] in
            guard let self = self else { return }

            var notifyPort: IONotificationPortRef?
            var notifier: io_object_t = 0
            let refcon = Unmanaged.passUnretained(self).toOpaque()

            let callback: IOServiceInterestCallback = { refcon, _, messageType, messageArgument in
                guard let refcon = refcon else { return }
                let engine = Unmanaged<SwitcherEngine>.fromOpaque(refcon).takeUnretainedValue()
                let message = messageType & 0xffff0000

                // IOKit power notifications. These match kIOMessageCanSystemSleep,
                // kIOMessageSystemWillSleep and kIOMessageSystemHasPoweredOn.
                switch message {
                case 0xe0000270, 0xe0000280:
                    IOAllowPowerChange(engine.powerConnection, Int(bitPattern: messageArgument))
                case 0xe0000300:
                    engine.systemDidWake()
                default:
                    break
                }
            }

            let connection = IORegisterForSystemPower(refcon, &notifyPort, callback, &notifier)
            guard connection != 0, let port = notifyPort else {
                self.log("Warning: unable to register for system power notifications; wake handling is disabled.")
                return
            }

            self.powerConnection = connection
            self.powerNotifier = notifier
            self.powerNotifyPort = port

            let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            self.log("Power notifications active (wake detection enabled).")
            CFRunLoopRun()
        }
        thread.name = "com.twsmicswitcher.power"
        thread.start()
    }

    private func systemDidWake() {
        log("System wake detected. Re-checking audio routing.")
        workQueue.async { [weak self] in
            guard let self = self else { return }

            let currentBT = CoreAudioService.shared.getAllDevices().filter { $0.isBluetooth }
            let currentIDs = Set(currentBT.map { $0.id })
            self.knownBluetoothDeviceIDs = currentIDs

            if let override = self.manualOverrideDeviceID, !currentIDs.contains(override) {
                self.manualOverrideDeviceID = nil
            }

            if let input = CoreAudioService.shared.getDefaultInputDevice(),
               input.isBluetooth,
               self.manualOverrideDeviceID == input.id {
                self.log("Wake: retaining manual Bluetooth input '\(input.name)'.")
                return
            }

            // Reconnects can reuse the same AudioObjectID across sleep, so treat
            // every connected Bluetooth device as eligible after wake.
            if !currentIDs.isEmpty {
                self.openConnectionWindow(deviceIDs: currentIDs, seconds: 10)
                self.scheduleVerifications(in: [1.0, 3.0, 6.0])
            }

            self.evaluateAndSwitch(reason: "wake")
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
