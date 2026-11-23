import Foundation
import AppKit

func printUsage() {
    print("""
    🎧 TWS Mic Switcher for macOS
    Automatically keeps your microphone input on your MacBook Air whenever TWS / Bluetooth headphones connect.
    
    Usage:
      tws-mic-switcher [command]
    
    Commands:
      menubar             Run as a macOS Menu Bar app (default if no argument provided in interactive terminal)
      daemon              Run as headless background daemon (used by LaunchAgent)
      status              Print current audio devices and switcher state
      switch              Manually switch default input to MacBook Air built-in microphone now
      enable              Enable automatic mic switching
      disable             Pause/disable automatic mic switching
      notify <on|off>     Turn notification banners on or off
      test-notify [sound] Send a sample notification to preview styling (e.g. Pop, Glass, Tink)
      help                Show this help menu
    
    Background Service:
      To install and run silently as a macOS LaunchAgent on boot:
        ./scripts/install.sh
      To uninstall:
        ./scripts/uninstall.sh
    """)
}

func handleStatus() {
    print("=== TWS Mic Switcher Status ===")
    let config = ConfigManager.shared.config
    print("Feature Enabled:       \(config.enabled ? "✅ YES" : "⏸️ PAUSED")")
    print("Notifications:         \(config.notificationsEnabled ? "🔔 ON" : "🔕 OFF")")
    print("Allow USB Inputs:      \(config.allowUSBInputs ? "YES (will not override USB mics)" : "NO")")
    
    print("\n--- Current Audio Routing ---")
    if let currentIn = CoreAudioService.shared.getDefaultInputDevice() {
        let tag = currentIn.isBuiltIn ? " (Internal Mic ✅)" : (currentIn.isBluetooth ? " (Bluetooth ⚠️)" : "")
        print("Default Input:         \(currentIn.name) [\(currentIn.transportName)]\(tag)")
        print("                       ID: \(currentIn.id) | UID: \(currentIn.uid)")
    } else {
        print("Default Input:         None detected")
    }
    
    if let currentOut = CoreAudioService.shared.getDefaultOutputDevice() {
        print("Default Output:        \(currentOut.name) [\(currentOut.transportName)]")
        print("                       ID: \(currentOut.id) | UID: \(currentOut.uid)")
    } else {
        print("Default Output:        None detected")
    }
    
    print("\n--- Target Built-In Microphone ---")
    if let builtIn = CoreAudioService.shared.findBuiltInMicrophone(preferredUID: config.preferredInputUID) {
        print("Built-In Mic:          \(builtIn.name) (ID: \(builtIn.id), UID: \(builtIn.uid))")
    } else {
        print("Built-In Mic:          ⚠️ Not found (Lid closed in clamshell mode or permission restricted)")
    }
    
    print("\n--- All Detected Audio Devices ---")
    let devices = CoreAudioService.shared.getAllDevices()
    for d in devices {
        print("• \(d)")
    }
    print("================================")
}

func handleSwitch() {
    print("Forcing microphone switch to MacBook built-in microphone...")
    let result = SwitcherEngine.shared.forceSwitchToBuiltIn()
    if result.success {
        print("✅ \(result.message)")
    } else {
        print("❌ Error: \(result.message)")
        exit(1)
    }
}

func runDaemon() {
    print("Starting TWS Mic Switcher daemon in headless mode...")
    SwitcherEngine.shared.start()
    dispatchMain()
}

func runMenuBar() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // Do not show in Dock
    
    let menuController = MenuBarController()
    menuController.setup()
    
    SwitcherEngine.shared.start()
    
    app.run()
}

// MARK: - CLI Dispatch

let args = CommandLine.arguments

if args.count <= 1 {
    // If no argument, run menubar if UI available, else daemon
    runMenuBar()
} else {
    switch args[1].lowercased() {
    case "daemon":
        runDaemon()
    case "menubar":
        runMenuBar()
    case "status":
        handleStatus()
    case "switch":
        handleSwitch()
    case "enable":
        ConfigManager.shared.setEnabled(true)
        print("✅ TWS Mic Switcher enabled.")
        SwitcherEngine.shared.evaluateAndSwitch(reason: "CLI Enable")
    case "disable":
        ConfigManager.shared.setEnabled(false)
        print("⏸️ TWS Mic Switcher disabled (paused).")
    case "notify-dispatch":
        // Internal command called within TWS Mic Switcher.app to display native bundled banner
        if args.count >= 5 {
            let title = args[2]
            let subtitle = args[3]
            let message = args[4]
            let sound = args.count > 5 ? args[5] : "Pop"
            NotificationHelper.shared.deliverViaNSUserNotification(
                title: title,
                subtitle: subtitle,
                message: message,
                sound: sound
            )
            // Keep runloop alive for 1 second to deliver
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        }
    case "test-notify":
        let sound = args.count > 2 ? args[2] : "Pop"
        let sampleDevice = CoreAudioService.shared.getDefaultOutputDevice()?.name ?? "AirPods Pro"
        let builtInName = CoreAudioService.shared.findBuiltInMicrophone()?.name ?? "MacBook Air Microphone"
        print("🔔 Sending sample notification with sound '\(sound)'...")
        NotificationHelper.shared.sendNotification(
            title: "🎧 \(sampleDevice) Connected",
            subtitle: "🎙️ Mic Kept on \(builtInName)",
            message: "✨ Studio-grade mic active • HD Stereo output preserved",
            sound: sound
        )
        print("✅ Sample notification dispatched! Check your top-right screen corner.")
    case "notify":
        if args.count > 2 && args[2].lowercased() == "off" {
            ConfigManager.shared.setNotificationsEnabled(false)
            print("🔕 Notifications turned off.")
        } else {
            ConfigManager.shared.setNotificationsEnabled(true)
            print("🔔 Notifications turned on.")
        }
    case "help", "--help", "-h":
        printUsage()
    default:
        print("Unknown command: \(args[1])\n")
        printUsage()
        exit(1)
    }
}
