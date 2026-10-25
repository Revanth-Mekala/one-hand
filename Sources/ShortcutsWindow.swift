import Cocoa

/// Small editor for the shortcut list and settings. Created on first use; closing it only hides it.
final class ShortcutsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let store: ConfigStore
    private let engine: Engine
    private let onSave: (AppConfig) -> Void
    private var config: AppConfig
    private var rows: [ShortcutEntry]

    private let table = NSTableView()
    private let modeLabel = NSTextField(labelWithString: "")
    private let modeButton = NSButton(title: "Turn On", target: nil, action: nil)
    private let recordButton = NSButton(title: "Record Trigger", target: nil, action: nil)
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let holdField = NSTextField(string: "")
    private let tapField = NSTextField(string: "")
    private let speedField = NSTextField(string: "")
    private let soundsCheck = NSButton(checkboxWithTitle: "Sounds", target: nil, action: nil)
    private let startOnCheck = NSButton(checkboxWithTitle: "Start in one-hand mode", target: nil, action: nil)

    private var keyMonitor: Any?
    private var recordingModifier: UInt64?

    init(store: ConfigStore, engine: Engine, config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        self.store = store
        self.engine = engine
        self.config = config
        self.rows = config.shortcuts
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.title = "One Hand — Shortcuts"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 540, height: 380)
        super.init(window: window)
        window.delegate = self
        buildUI()
        load(config)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func load(_ config: AppConfig) {
        self.config = config
        rows = config.shortcuts
        holdField.stringValue = formatSeconds(config.toggleHoldSeconds)
        tapField.stringValue = formatSeconds(config.tapMaxSeconds)
        speedField.stringValue = formatSeconds(config.scrollSpeed)
        soundsCheck.state = config.playSounds ? .on : .off
        startOnCheck.state = config.startEnabled ? .on : .off
        table.reloadData()
        refreshMode()
    }

    func refreshMode() {
        let on = engine.enabled
        modeLabel.stringValue = "One-hand mode is \(on ? "ON" : "OFF")"
        modeLabel.textColor = on ? .controlAccentColor : .labelColor
        modeButton.title = on ? "Turn Off" : "Turn On"
    }

    func showMessage(_ text: String, isError: Bool) {
        messageLabel.stringValue = text
        messageLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    // MARK: - Layout

    private func buildUI() {
        guard let content = window?.contentView else { return }

        modeLabel.font = .boldSystemFont(ofSize: 14)
        modeButton.target = self
        modeButton.action = #selector(toggleMode)
        let modeHint = NSTextField(labelWithString: "Hold \(KeyNames.symbol(for: config.toggleKey)) for \(formatSeconds(config.toggleHoldSeconds)) s anywhere to toggle. Shortcuts pause while this window is focused.")
        modeHint.textColor = .secondaryLabelColor
        modeHint.font = .systemFont(ofSize: 11)
        modeHint.lineBreakMode = .byTruncatingTail
        modeHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView()
        header.addView(modeLabel, in: .leading)
        header.addView(modeButton, in: .trailing)

        for (id, title, width) in [("trigger", "Trigger", 130.0), ("action", "Action", 170.0), ("note", "Note", 240.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = CGFloat(width)
            column.minWidth = 60
            column.isEditable = true
            if id != "note", let cell = column.dataCell as? NSTextFieldCell {
                cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            }
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true

        recordButton.target = self
        recordButton.action = #selector(recordTrigger)
        let buttons = NSStackView()
        for view in [button("+", #selector(addRow)), button("−", #selector(removeRow)), recordButton] {
            buttons.addView(view, in: .leading)
        }
        for view in [button("Reset to Defaults", #selector(resetDefaults)), button("Revert", #selector(revert)),
                     button("Save", #selector(save), isDefault: true)] {
            buttons.addView(view, in: .trailing)
        }

        let settings = NSStackView(views: [
            labeled("Hold to toggle (s)", holdField),
            labeled("Tap (s)", tapField),
            labeled("Scroll speed", speedField),
            soundsCheck,
            startOnCheck,
        ])
        settings.spacing = 14

        let help = NSTextField(wrappingLabelWithString: """
        Trigger: a key with optional modifiers — n, space, shift+, , ctrl+j, f5. A lone modifier (opt) means tap it.
        Action: a keystroke (cmd+c, esc, cmd+shift+4), scroll:up / down / left / right (hold to keep scrolling), \
        shell:<command>, or toggle. Double-click a cell to edit.
        """)
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        messageLabel.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [header, modeHint, scroll, buttons, settings, help, messageLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        for view in [header, modeHint, scroll, buttons, help, messageLabel] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func button(_ title: String, _ action: Selector, isDefault: Bool = false) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        if isDefault { button.keyEquivalent = "\r" }
        return button
    }

    private func labeled(_ title: String, _ field: NSTextField) -> NSView {
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 46).isActive = true
        let stack = NSStackView(views: [NSTextField(labelWithString: title), field])
        stack.spacing = 4
        return stack
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        switch tableColumn?.identifier.rawValue {
        case "trigger": return rows[row].trigger
        case "action": return rows[row].action
        default: return rows[row].note ?? ""
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard row < rows.count else { return }
        let text = (object as? String ?? "").trimmingCharacters(in: .whitespaces)
        switch tableColumn?.identifier.rawValue {
        case "trigger": rows[row].trigger = text
        case "action": rows[row].action = text
        default: rows[row].note = text.isEmpty ? nil : text
        }
        showMessage("Unsaved changes.", isError: false)
    }

    /// Cells that don't parse are shown in red.
    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        guard let cell = cell as? NSTextFieldCell, row < rows.count else { return }
        var valid = true
        switch tableColumn?.identifier.rawValue {
        case "trigger": valid = Trigger.parse(rows[row].trigger) != nil
        case "action": valid = Action.parse(rows[row].action) != nil
        default: break
        }
        cell.textColor = valid ? .labelColor : .systemRed
    }

    // MARK: - Buttons

    @objc private func toggleMode() {
        engine.setEnabled(!engine.enabled)
    }

    @objc private func addRow() {
        rows.append(ShortcutEntry(trigger: "", action: "", note: nil))
        table.reloadData()
        let row = rows.count - 1
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        table.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func removeRow() {
        let row = table.selectedRow
        guard row >= 0, row < rows.count else { return }
        window?.makeFirstResponder(table)
        rows.remove(at: row)
        table.reloadData()
        showMessage("Unsaved changes.", isError: false)
    }

    @objc private func resetDefaults() {
        let current = config
        load(AppConfig())
        config = current // keep the saved config until Save is pressed
        showMessage("Defaults restored — press Save to keep them.", isError: false)
    }

    @objc private func revert() {
        load(store.load().config)
        showMessage("Reverted to the saved config.", isError: false)
    }

    @objc private func save() {
        stopRecording()
        window?.makeFirstResponder(nil) // commit any in-progress cell edit
        var new = config
        new.shortcuts = rows.filter { !($0.trigger.isEmpty && $0.action.isEmpty) }
        new.playSounds = soundsCheck.state == .on
        new.startEnabled = startOnCheck.state == .on
        guard let hold = Double(holdField.stringValue), let tap = Double(tapField.stringValue),
              let speed = Double(speedField.stringValue) else {
            showMessage("Hold, tap and scroll speed must be numbers.", isError: true)
            return
        }
        new.toggleHoldSeconds = hold
        new.tapMaxSeconds = tap
        new.scrollSpeed = speed

        let errors = new.validationErrors()
        guard errors.isEmpty else {
            showMessage(errors.joined(separator: "\n"), isError: true)
            table.reloadData()
            return
        }
        do {
            try store.save(new)
        } catch {
            showMessage("Couldn't save: \(error.localizedDescription)", isError: true)
            return
        }
        config = new
        rows = new.shortcuts
        table.reloadData()
        onSave(new)
        showMessage("Saved ✓", isError: false)
    }

    // MARK: - Recording

    @objc private func recordTrigger() {
        if keyMonitor != nil {
            stopRecording()
            showMessage("Recording cancelled.", isError: false)
            return
        }
        let row = table.selectedRow
        guard row >= 0, row < rows.count else {
            showMessage("Select a row, click Record Trigger, then press the key you want.", isError: false)
            return
        }
        window?.makeFirstResponder(table)
        recordButton.title = "Press a key…"
        recordingModifier = nil
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            return self.record(event, row: row)
        }
    }

    private func record(_ event: NSEvent, row: Int) -> NSEvent? {
        let mods = Self.cgModifiers(event.modifierFlags)
        if event.type == .keyDown {
            finishRecording(KeyCombo(keyCode: event.keyCode, mods: mods), row: row)
            return nil
        }
        // A modifier pressed and released on its own records a tap trigger such as "opt".
        if mods == 0, let tapped = recordingModifier {
            finishRecording(KeyCombo(keyCode: nil, mods: tapped), row: row)
        } else {
            recordingModifier = mods.nonzeroBitCount == 1 ? mods : nil
        }
        return event
    }

    private func finishRecording(_ combo: KeyCombo, row: Int) {
        stopRecording()
        guard row < rows.count else { return }
        rows[row].trigger = KeyNames.format(combo)
        table.reloadData()
        showMessage("Trigger set to “\(rows[row].trigger)” — press Save to keep it.", isError: false)
    }

    private func stopRecording() {
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        recordButton.title = "Record Trigger"
    }

    private static func cgModifiers(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        var mods: UInt64 = 0
        if flags.contains(.command) { mods |= CGEventFlags.maskCommand.rawValue }
        if flags.contains(.shift) { mods |= CGEventFlags.maskShift.rawValue }
        if flags.contains(.option) { mods |= CGEventFlags.maskAlternate.rawValue }
        if flags.contains(.control) { mods |= CGEventFlags.maskControl.rawValue }
        return mods
    }

    // MARK: - Window

    func windowDidBecomeKey(_ notification: Notification) {
        engine.paused = true // so typing into the table isn't remapped
    }

    func windowDidResignKey(_ notification: Notification) {
        engine.paused = false
        stopRecording()
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
        engine.paused = false
        DispatchQueue.main.async { NSApp.hide(nil) } // hand focus back to the previous app
    }
}
