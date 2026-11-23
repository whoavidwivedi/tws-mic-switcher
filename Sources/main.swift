import Foundation
import AppKit

func printUsage() {
    print("""
    tws-mic-switcher

    Keeps default audio input on Mac built-in microphone when Bluetooth headphones connect.

    Usage:
      tws-mic-switcher [command]

    Commands:
      status            Print current audio devices and switcher state
      switch            Manually switch default input to built-in microphone
      enable            Enable automatic switching
      disable           Disable/pause automatic switching
      version           Print the installed version
      update [--check]  Check for, or install, the latest release
      daemon            Run headless daemon process (used by LaunchAgent)
      menubar           Run with menu bar extra
      help              Show this help text
    """)
}

func handleStatus() {
    print("tws-mic-switcher status")
    let config = ConfigManager.shared.config
    print("  Version:         \(appVersion)")
    print("  State:           \(config.enabled ? "enabled" : "paused")")
    print("  Allow USB:       \(config.allowUSBInputs)")
    
    print("\nRouting:")
    if let currentIn = CoreAudioService.shared.getDefaultInputDevice() {
        let note = currentIn.isBuiltIn ? " [built-in]" : (currentIn.isBluetooth ? " [bluetooth]" : "")
        print("  Default Input:   \(currentIn.name)\(note)")
        print("                   id: \(currentIn.id), uid: \(currentIn.uid)")
    } else {
        print("  Default Input:   none")
    }
    
    if let currentOut = CoreAudioService.shared.getDefaultOutputDevice() {
        print("  Default Output:  \(currentOut.name) [\(currentOut.transportName)]")
        print("                   id: \(currentOut.id), uid: \(currentOut.uid)")
    } else {
        print("  Default Output:  none")
    }
    
    print("\nBuilt-in Microphone:")
    if let builtIn = CoreAudioService.shared.findBuiltInMicrophone(preferredUID: config.preferredInputUID) {
        print("  Target:          \(builtIn.name) (id: \(builtIn.id), uid: \(builtIn.uid))")
    } else {
        print("  Target:          not found")
    }
    
    print("\nConnected Devices:")
    let devices = CoreAudioService.shared.getAllDevices()
    for d in devices {
        print("  - \(d)")
    }
}

func handleSwitch() {
    let result = SwitcherEngine.shared.forceSwitchToBuiltIn()
    if result.success {
        print(result.message)
    } else {
        fputs("error: \(result.message)\n", stderr)
        exit(1)
    }
}

func runDaemon() {
    SwitcherEngine.shared.start()
    dispatchMain()
}

func runMenuBar() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    
    let menuController = MenuBarController()
    menuController.setup()
    
    SwitcherEngine.shared.start()
    app.run()
}

// MARK: - Entry point

let args = CommandLine.arguments

if args.count <= 1 {
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
        print("tws-mic-switcher enabled.")
        SwitcherEngine.shared.evaluateAndSwitch(reason: "cli-enable")
    case "disable":
        ConfigManager.shared.setEnabled(false)
        print("tws-mic-switcher disabled.")
    case "version", "--version", "-v":
        print("tws-mic-switcher \(appVersion)")
    case "update":
        let checkOnly = args.dropFirst(2).contains("--check")
        exit(Updater.run(checkOnly: checkOnly))
    case "help", "--help", "-h":
        printUsage()
    default:
        fputs("unknown command: \(args[1])\n\n", stderr)
        printUsage()
        exit(1)
    }
}
