import AppKit
import CoreAudio

public final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    
    public override init() {
        super.init()
    }
    
    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            if #available(macOS 11.0, *),
               let image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "TWS Mic Switcher") {
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
                button.image = image.withSymbolConfiguration(config)
            } else {
                button.title = "🎧"
            }
            button.toolTip = "TWS Mic Switcher"
        }
        
        menu.delegate = self
        statusItem?.menu = menu
        refreshMenu()
    }
    
    public func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }
    
    @objc private func refreshMenu() {
        menu.removeAllItems()
        
        let config = ConfigManager.shared.config
        let isEnabled = config.enabled
        
        // Status header
        let titleItem = NSMenuItem(
            title: isEnabled ? "TWS Mic Switcher: Active" : "TWS Mic Switcher: Paused",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Audio Devices status
        let currentIn = CoreAudioService.shared.getDefaultInputDevice()
        let currentOut = CoreAudioService.shared.getDefaultOutputDevice()
        
        let inItem = NSMenuItem(
            title: "Input:  \(currentIn?.name ?? "None") (\(currentIn?.transportName ?? "Unknown"))",
            action: nil,
            keyEquivalent: ""
        )
        inItem.isEnabled = false
        if let currentIn = currentIn, currentIn.isBuiltIn {
            inItem.state = .on
        }
        menu.addItem(inItem)
        
        let outItem = NSMenuItem(
            title: "Output: \(currentOut?.name ?? "None") (\(currentOut?.transportName ?? "Unknown"))",
            action: nil,
            keyEquivalent: ""
        )
        outItem.isEnabled = false
        menu.addItem(outItem)
        menu.addItem(NSMenuItem.separator())
        
        // Toggle Enabled
        let toggleEnableItem = NSMenuItem(
            title: "Auto-Switch to MacBook Mic",
            action: #selector(toggleEnabled),
            keyEquivalent: "e"
        )
        toggleEnableItem.target = self
        toggleEnableItem.state = isEnabled ? .on : .off
        menu.addItem(toggleEnableItem)
        
        // Toggle Notifications
        let toggleNotifItem = NSMenuItem(
            title: "Show Desktop Notifications",
            action: #selector(toggleNotifications),
            keyEquivalent: "n"
        )
        toggleNotifItem.target = self
        toggleNotifItem.state = config.notificationsEnabled ? .on : .off
        menu.addItem(toggleNotifItem)
        menu.addItem(NSMenuItem.separator())
        
        // Action: Force switch now
        let forceItem = NSMenuItem(
            title: "Switch to Built-in Mic Now",
            action: #selector(forceSwitch),
            keyEquivalent: "s"
        )
        forceItem.target = self
        menu.addItem(forceItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit TWS Mic Switcher",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func toggleEnabled() {
        let current = ConfigManager.shared.config.enabled
        ConfigManager.shared.setEnabled(!current)
        if !current {
            SwitcherEngine.shared.evaluateAndSwitch(reason: "User Enabled")
        }
        refreshMenu()
    }
    
    @objc private func toggleNotifications() {
        let current = ConfigManager.shared.config.notificationsEnabled
        ConfigManager.shared.setNotificationsEnabled(!current)
        refreshMenu()
    }
    
    @objc private func forceSwitch() {
        let result = SwitcherEngine.shared.forceSwitchToBuiltIn()
        SwitcherEngine.shared.log(result.message)
        refreshMenu()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
