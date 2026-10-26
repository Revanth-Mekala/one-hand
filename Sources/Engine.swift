import CoreGraphics
import Foundation

extension Notification.Name {
    static let oneHandModeChanged = Notification.Name("OneHandModeChanged")
}

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<Engine>.fromOpaque(refcon).takeUnretainedValue().handle(type, event)
}

/// Watches the keyboard through a CGEvent tap and turns triggers into actions.
/// Everything runs on the main run loop and only wakes up when a key is pressed,
/// so it uses no CPU while idle. The only timers are the hold-to-toggle timer
/// (while the toggle key is held alone) and the scroll timer (while a scroll key is held).
final class Engine {
    /// Stamped on every event we post so the tap lets our own events through untouched.
    private static let marker: Int64 = 0x4F4E_4548 // "ONEH"

    private(set) var enabled = false
    /// Pauses remapping (e.g. while the shortcuts window is focused). The toggle gesture still works.
    var paused = false
    var isRunning: Bool { tap != nil }

    private var tap: CFMachPort?
    private var keyActions: [KeyCombo: Action] = [:]
    private var tapActions: [UInt64: Action] = [:]
    private var toggleFlag = CGEventFlags.maskAlternate.rawValue
    private var holdSeconds = 3.0
    private var tapMaxSeconds = 0.5
    private var scrollSpeed = 14.0

    /// Trigger keys currently held down whose key-down we swallowed, so we swallow their key-up too.
    private var heldKeys: [CGKeyCode: Action] = [:]
    /// A modifier pressed on its own: a quick release is a tap, holding the toggle key toggles the mode.
    private var pendingModifier: (flag: UInt64, since: TimeInterval)?
    private var holdTimer: DispatchSourceTimer?
    private var scrollTimer: DispatchSourceTimer?
    private var scrollKey: CGKeyCode = 0
    private var scrollStart: TimeInterval = 0
    private var scrollDirection: (dx: Int32, dy: Int32) = (0, 0)
    /// Modifiers a hold action is keeping down, and the trigger key holding them.
    private var heldMods: UInt64 = 0
    private var holdTrigger: CGKeyCode?
    private let source = CGEventSource(stateID: .hidSystemState)

    private var isRemapping: Bool { enabled && !paused }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func apply(_ config: AppConfig) {
        keyActions = [:]
        tapActions = [:]
        for entry in config.shortcuts {
            guard let trigger = Trigger.parse(entry.trigger), let action = Action.parse(entry.action) else { continue }
            switch trigger {
            case .key(let combo): keyActions[combo] = action
            case .modifierTap(let flag): tapActions[flag] = action
            }
        }
        if case .modifierTap(let flag)? = Trigger.parse(config.toggleKey) { toggleFlag = flag }
        holdSeconds = max(0.2, config.toggleHoldSeconds)
        tapMaxSeconds = max(0.05, config.tapMaxSeconds)
        scrollSpeed = max(1, config.scrollSpeed)
    }

    /// Installs the event tap. Fails until the app has Accessibility permission.
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        return true
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if !on {
            stopScrolling()
            releaseHold()
        }
        NotificationCenter.default.post(name: .oneHandModeChanged, object: self)
    }

    // MARK: - Event handling

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == Engine.marker { return pass }

        switch type {
        case .flagsChanged:
            modifiersChanged(event)
            return pass
        case .keyDown, .keyUp:
            if (type == .keyDown ? keyDown(event) : keyUp(event)) { return nil }
            // Keys passing through during a hold get the held modifiers too.
            if heldMods != 0 { event.flags = CGEventFlags(rawValue: event.flags.rawValue | heldMods) }
            return pass
        default: // mouse click: Option-click etc. is not a tap or a hold
            cancelModifierGesture()
            return pass
        }
    }

    private func modifiersChanged(_ event: CGEvent) {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let flag = KeyNames.modifierFlag(forKeyCode: code) else {
            cancelModifierGesture()
            return
        }
        let mods = event.flags.rawValue & KeyCombo.modifierMask

        if mods & flag != 0 { // pressed
            if mods == flag {
                pendingModifier = (flag, now)
                if flag == toggleFlag { startHoldTimer() } else { cancelHoldTimer() }
            } else {
                cancelModifierGesture()
            }
            return
        }

        // released
        let pending = pendingModifier
        cancelModifierGesture()
        guard let tapped = pending, tapped.flag == flag, now - tapped.since <= tapMaxSeconds,
              isRemapping, let action = tapActions[flag] else { return }
        perform(action, key: nil)
    }

    /// Returns true to swallow the event.
    private func keyDown(_ event: CGEvent) -> Bool {
        cancelModifierGesture()
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Let go of a hold whose key-up never reached us (e.g. the tap was briefly disabled).
        if let trigger = holdTrigger, trigger != code, !CGEventSource.keyState(.hidSystemState, key: trigger) {
            heldKeys[trigger] = nil
            releaseHold()
        }

        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0, let action = heldKeys[code] {
            // Holding a keystroke trigger repeats it like the real shortcut would; scrolling is timer-driven.
            if case .keystroke = action { perform(action, key: code) }
            return true
        }

        guard isRemapping else { return false }
        // Our own held modifiers can show up in the event's flags; they aren't part of the trigger.
        let mods = event.flags.rawValue & KeyCombo.modifierMask & ~heldMods
        let combo = KeyCombo(keyCode: code, mods: mods)
        guard let action = keyActions[combo] else { return false }
        heldKeys[code] = action
        perform(action, key: code)
        return true
    }

    private func keyUp(_ event: CGEvent) -> Bool {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard heldKeys.removeValue(forKey: code) != nil else { return false }
        if scrollTimer != nil && scrollKey == code { stopScrolling() }
        if holdTrigger == code { releaseHold() }
        return true
    }

    // MARK: - Actions

    private func perform(_ action: Action, key: CGKeyCode?) {
        switch action {
        case .keystroke(let combo):
            post(combo)
        case .scroll(let dx, let dy):
            if let key = key {
                startScrolling(dx: dx, dy: dy, key: key)
            } else { // tap trigger: nothing to hold, so scroll one chunk
                let step = Int32(scrollSpeed * 8)
                postScroll(dx: dx * step, dy: dy * step)
            }
        case .shell(let command):
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            try? process.run()
        case .toggleMode:
            setEnabled(!enabled)
        case .hold(let combo):
            guard let key = key else { // tap trigger: nothing to hold, so just press it once
                post(combo)
                return
            }
            releaseHold()
            holdTrigger = key
            heldMods = combo.mods
            postModifiers(combo.mods, down: true)
            if let code = combo.keyCode { post(KeyCombo(keyCode: code, mods: 0)) }
        }
    }

    /// Posts a key press. While a hold is active its modifiers are added, so "tab" becomes ⌘Tab.
    private func post(_ combo: KeyCombo) {
        guard let code = combo.keyCode else { return }
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown) else { continue }
            event.flags = CGEventFlags(rawValue: combo.mods | heldMods)
            event.setIntegerValueField(.eventSourceUserData, value: Engine.marker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func releaseHold() {
        guard heldMods != 0 else { return }
        let mods = heldMods
        heldMods = 0
        holdTrigger = nil
        postModifiers(mods, down: false)
    }

    /// Presses or releases modifier keys the way a keyboard does, one flags-changed event per key.
    private func postModifiers(_ mods: UInt64, down: Bool) {
        var flags: UInt64 = down ? 0 : mods
        for (flag, code) in KeyNames.modifierKeys where mods & flag != 0 {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            if down { flags |= flag } else { flags &= ~flag }
            event.type = .flagsChanged
            event.flags = CGEventFlags(rawValue: flags)
            event.setIntegerValueField(.eventSourceUserData, value: Engine.marker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func postScroll(dx: Int32, dy: Int32) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                                  wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
        event.flags = [] // a held Shift would otherwise turn it into a horizontal scroll
        event.setIntegerValueField(.eventSourceUserData, value: Engine.marker)
        event.post(tap: .cghidEventTap)
    }

    private func startScrolling(dx: Int32, dy: Int32, key: CGKeyCode) {
        stopScrolling()
        scrollKey = key
        scrollDirection = (dx, dy)
        scrollStart = now
        scrollTick() // a quick tap still scrolls a little

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(16), repeating: .milliseconds(16), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.scrollTick() }
        timer.resume()
        scrollTimer = timer
    }

    private func scrollTick() {
        // Stop if the key-up never reached us (e.g. the tap was briefly disabled).
        if scrollTimer != nil && !CGEventSource.keyState(.hidSystemState, key: scrollKey) {
            stopScrolling()
            heldKeys[scrollKey] = nil
            return
        }
        let ramp = min(1.0, 0.3 + (now - scrollStart) * 2.5) // ease in over ~0.3 s
        let step = Int32((scrollSpeed * ramp).rounded())
        postScroll(dx: scrollDirection.dx * step, dy: scrollDirection.dy * step)
    }

    private func stopScrolling() {
        scrollTimer?.cancel()
        scrollTimer = nil
    }

    // MARK: - Modifier tap / hold

    private func startHoldTimer() {
        cancelHoldTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + holdSeconds)
        timer.setEventHandler { [weak self] in self?.holdTimerFired() }
        timer.resume()
        holdTimer = timer
    }

    private func holdTimerFired() {
        cancelHoldTimer()
        let held = CGEventSource.flagsState(.hidSystemState).rawValue & KeyCombo.modifierMask
        let stillHolding = pendingModifier?.flag == toggleFlag && held == toggleFlag
        pendingModifier = nil // releasing the key afterwards is not a tap
        if stillHolding { setEnabled(!enabled) }
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    private func cancelModifierGesture() {
        pendingModifier = nil
        cancelHoldTimer()
    }
}
