import AppKit
import Carbon.HIToolbox
import LunaCore
import SwiftUI

/// Global shortcuts through Carbon's hot keys, which work in every app without any permission.
final class HotKeys {
    static let shared = HotKeys()

    var onAction: (ShortcutAction) -> Void = { _ in }
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: ShortcutAction] = [:]
    private var installed = false
    /// Paused while a shortcut is being recorded, so pressing an existing one records it instead of firing.
    var paused = false

    func register(_ shortcuts: [ShortcutAction: KeyCombo]) {
        installHandler()
        for ref in registered { UnregisterEventHotKey(ref) }
        registered.removeAll()
        actions.removeAll()
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let combo = shortcuts[action] else { continue }
            let id = EventHotKeyID(signature: 0x4C55_4E41, id: UInt32(index + 1))  // "LUNA"
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
                let ref
            {
                registered.append(ref)
                actions[id.id] = action
            }
        }
    }

    fileprivate func fire(_ id: UInt32) {
        guard !paused, let action = actions[id] else { return }
        onAction(action)
    }

    private func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &spec, nil, nil)
    }
}

/// Carbon calls this on the main thread. A plain function, not a closure written in main-actor code, so
/// Swift adds no isolation check of its own to a callback it doesn't control.
nonisolated private func hotKeyPressed(
    _ handler: EventHandlerCallRef?, _ event: EventRef?, _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    var id = EventHotKeyID()
    GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
        MemoryLayout<EventHotKeyID>.size, nil, &id)
    let number = id.id
    DispatchQueue.main.async { HotKeys.shared.fire(number) }
    return noErr
}

/// Shortcuts as text: "⌃⌥⌘B".
enum KeyNames {
    static func string(for combo: KeyCombo) -> String {
        var text = ""
        if combo.modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if combo.modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if combo.modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if combo.modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyName(combo.keyCode)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static let special: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]

    static func isFunctionKey(_ code: UInt32) -> Bool {
        special[code]?.hasPrefix("F") == true
    }

    static func keyName(_ code: UInt32) -> String {
        if let name = special[code] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Click, then press a shortcut. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    var combo: KeyCombo?
    var onChange: (KeyCombo?) -> Void

    @ViewState private var recording = false
    @ViewState private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type a shortcut…" : combo.map(KeyNames.string(for:)) ?? "Record Shortcut")
                    .font(.system(size: 12, weight: combo == nil || recording ? .regular : .medium).monospaced())
                    .foregroundStyle(recording ? Color.accentColor : combo == nil ? Color.secondary : Color.primary)
                    .frame(minWidth: 128)
            }
            .buttonStyle(.bordered)
            if combo != nil, !recording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeys.shared.paused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                let code = UInt32(event.keyCode)
                if code == 53 {
                    stop()
                } else if code == 51 || code == 117 {
                    onChange(nil)
                    stop()
                } else {
                    let modifiers = KeyNames.carbonModifiers(event.modifierFlags)
                    let needsModifier = modifiers & UInt32(cmdKey | optionKey | controlKey) == 0
                    if needsModifier && !KeyNames.isFunctionKey(code) {
                        NSSound.beep()
                    } else {
                        onChange(KeyCombo(keyCode: code, modifiers: modifiers))
                        stop()
                    }
                }
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        HotKeys.shared.paused = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
