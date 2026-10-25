import ApplicationServices
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ConfigStore()
    private let engine = Engine()
    private var config = AppConfig()

    private var statusItem: NSStatusItem!
    private let modeItem = NSMenuItem(title: "One-Hand Mode", action: #selector(toggleMode), keyEquivalent: "")
    private let hintItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let windowItem = NSMenuItem(title: "Show Shortcuts", action: #selector(toggleWindow), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "⚠︎ Grant Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private var windowController: ShortcutsWindowController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        setUpStatusItem()

        let loaded = store.load()
        config = loaded.config
        engine.apply(config)
        NotificationCenter.default.addObserver(self, selector: #selector(modeChanged),
                                               name: .oneHandModeChanged, object: engine)

        startEngine(promptForPermission: true)
        if config.startEnabled { engine.setEnabled(true) }
        refreshStatus()

        let errors = (loaded.error.map { [$0] } ?? []) + config.validationErrors()
        if !errors.isEmpty {
            showWindow()
            windowController?.showMessage(errors.joined(separator: "\n"), isError: true)
        }
    }

    // MARK: - Engine

    private func startEngine(promptForPermission: Bool) {
        if engine.start() {
            permissionTimer?.invalidate()
            permissionTimer = nil
        } else {
            if promptForPermission {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            // Retry quietly until permission is granted; stops as soon as the tap is installed.
            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(retryEngine),
                                                       userInfo: nil, repeats: true)
            }
        }
        refreshStatus()
    }

    @objc private func retryEngine() {
        startEngine(promptForPermission: false)
    }

    private func apply(_ newConfig: AppConfig) {
        config = newConfig
        engine.apply(newConfig)
    }

    @objc private func modeChanged() {
        if config.playSounds { NSSound(named: engine.enabled ? "Tink" : "Pop")?.play() }
        refreshStatus()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        hintItem.isEnabled = false
        for item in [modeItem, windowItem, permissionItem] { item.target = self }
        menu.addItem(modeItem)
        menu.addItem(hintItem)
        menu.addItem(.separator())
        menu.addItem(windowItem)
        menu.addItem(withTitle: "Open Config File", action: #selector(openConfigFile), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(permissionItem)
        menu.addItem(withTitle: "Quit One Hand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func refreshStatus() {
        let on = engine.enabled
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: on ? "hand.raised.fill" : "hand.raised",
                                   accessibilityDescription: on ? "One-hand mode on" : "One-hand mode off")
            button.image?.isTemplate = true
            button.contentTintColor = on ? .controlAccentColor : nil
            if button.image == nil { button.title = on ? "1H●" : "1H" }
        }
        modeItem.state = on ? .on : .off
        modeItem.title = on ? "One-Hand Mode: On" : "One-Hand Mode: Off"
        hintItem.title = "Hold \(KeyNames.symbol(for: config.toggleKey)) for \(formatSeconds(config.toggleHoldSeconds)) s to toggle"
        permissionItem.isHidden = engine.isRunning
        windowController?.refreshMode()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        windowItem.title = windowController?.window?.isVisible == true ? "Hide Shortcuts" : "Show Shortcuts"
    }

    @objc private func toggleMode() {
        engine.setEnabled(!engine.enabled)
    }

    @objc private func toggleWindow() {
        if let window = windowController?.window, window.isVisible {
            window.performClose(nil)
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        if windowController == nil {
            windowController = ShortcutsWindowController(store: store, engine: engine, config: config) { [weak self] saved in
                self?.apply(saved)
                self?.refreshStatus()
            }
        }
        windowController?.present()
    }

    @objc private func openConfigFile() {
        if !FileManager.default.fileExists(atPath: store.url.path) { try? store.save(config) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-t", store.url.path] // default text editor
        try? process.run()
    }

    @objc private func reloadConfig() {
        let loaded = store.load()
        apply(loaded.config)
        refreshStatus()
        windowController?.load(loaded.config)
        let errors = (loaded.error.map { [$0] } ?? []) + loaded.config.validationErrors()
        if !errors.isEmpty {
            showWindow()
            windowController?.showMessage(errors.joined(separator: "\n"), isError: true)
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Accessory apps have no visible menu bar, but the Edit menu's key equivalents
    /// are what make ⌘C / ⌘V / ⌘A work in the window's text fields.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit One Hand", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}

func formatSeconds(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(value)
}

extension KeyNames {
    /// "opt" → "⌥ Option", for display.
    static func symbol(for modifier: String) -> String {
        guard case .modifierTap(let flag)? = Trigger.parse(modifier) else { return modifier }
        switch flag {
        case CGEventFlags.maskAlternate.rawValue: return "⌥ Option"
        case CGEventFlags.maskCommand.rawValue: return "⌘ Command"
        case CGEventFlags.maskControl.rawValue: return "⌃ Control"
        default: return "⇧ Shift"
        }
    }
}
