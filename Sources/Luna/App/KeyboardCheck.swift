import AppKit
import LunaCore

/// `--preview --keyboard-check`: drives the panel's sliders with real key events, posted to Luna's own event
/// queue the way keystrokes arrive, and checks that arrows do nothing until Tab, that Tab and Shift-Tab move
/// between sliders and that the arrows then adjust the focused one. Needs no Accessibility permission (unlike
/// posting events to another app), so it runs from any terminal or script. Exits 0 on success.
@MainActor
struct KeyboardCheck {
    var model: AppModel
    private var failures = 0

    init(model: AppModel) {
        self.model = model
    }

    mutating func run() async {
        guard let panel = NSApp.windows.first(where: { $0 is LunaPanel }) else { return finish("no panel") }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))

        let start = positions()
        await press(124)
        check(positions() == start, "an arrow before Tab moves nothing")

        await press(48)
        // Tab stops at buttons too; Right moves only a slider. Record which slider each stop moves, if any.
        let forward = await walk(shift: false)
        print("  Tab reaches sliders in this order: \(forward)")
        check(SliderKeyboard.shared.active, "Tab turns on keyboard mode")
        check(Set(forward).count == sliderCount, "Tab reaches every brightness slider (\(sliderCount))")
        check(forward == forward.sorted(), "Tab goes top to bottom")
        let backward = await walk(shift: true)
        print("  Shift-Tab reaches sliders in this order: \(backward)")
        // Starting wherever Tab left off, Shift-Tab visits every slider going up (wrapping at the top).
        let first = model.controller.displays.count > 1 ? 0 : 1
        let offset = (backward.first ?? first) - first
        let order = (0..<sliderCount).map { first + (sliderCount + offset - $0) % sliderCount }
        check(backward == order, "Shift-Tab goes bottom to top")

        // A click (on the panel's header, clear of any control) hands control back to the mouse.
        await click(in: panel, at: NSPoint(x: Metrics.panelMargin + 8, y: panel.frame.height - Metrics.panelMargin - 8))
        check(!SliderKeyboard.shared.active, "a click ends keyboard mode")
        let clicked = positions()
        await press(124)
        check(positions() == clicked, "after the mouse takes over, arrows move nothing")
        finish(failures == 0 ? nil : "\(failures) check(s) failed")
    }

    /// Presses Right after each of up to 24 Tabs (or Shift-Tabs) and lists the sliders that moved, each once,
    /// in the order they were reached. The first stop is the slider already focused.
    private func walk(shift: Bool) async -> [Int] {
        var reached: [Int] = []
        for step in 0..<24 {
            if step > 0 { await press(48, shift: shift) }
            let before = positions()
            await press(shift ? 123 : 124)
            if let index = movedSlider(before, positions()), !reached.contains(index) { reached.append(index) }
        }
        return reached
    }

    /// Each display's brightness position.
    private func positions() -> [Double] { model.controller.displays.map(\.position) }

    /// The brightness sliders: one per display, plus All displays when there are several.
    private var sliderCount: Int {
        let count = model.controller.displays.count
        return count > 1 ? count + 1 : count
    }

    /// Which slider moved: 0 for All displays (every display moved), else 1 + the display's index.
    private func movedSlider(_ before: [Double], _ after: [Double]) -> Int? {
        let moved = before.indices.filter { before[$0] != after[$0] }
        if moved.isEmpty { return nil }
        if moved.count == before.count, before.count > 1 { return 0 }
        return moved[0] + 1
    }

    private func press(_ keyCode: UInt16, shift: Bool = false) async {
        let characters: String =
            switch keyCode {
            case 48: shift ? "\u{19}" : "\t"  // Shift-Tab types the back-tab character
            case 123: String(UnicodeScalar(NSLeftArrowFunctionKey)!)
            default: String(UnicodeScalar(NSRightArrowFunctionKey)!)
            }
        var flags: NSEvent.ModifierFlags = keyCode == 48 ? [] : [.numericPad, .function]
        if shift { flags.insert(.shift) }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
            else { continue }
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(Self.keyGap))
    }

    /// Time between key presses, like a quick typist. A busy Mac needs longer for SwiftUI to move the focus:
    /// LUNA_KEYCHECK_GAP_MS sets it.
    private static let keyGap = Int(ProcessInfo.processInfo.environment["LUNA_KEYCHECK_GAP_MS"] ?? "") ?? 250

    private func click(in window: NSWindow, at point: NSPoint) async {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard
                let event = NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { continue }
            NSApp.postEvent(event, atStart: false)
        }
        try? await Task.sleep(for: .milliseconds(250))
    }

    private mutating func check(_ ok: Bool, _ name: String) {
        print("\(ok ? "✓" : "✗") \(name)")
        if !ok { failures += 1 }
    }

    private func finish(_ failure: String?) {
        print(failure.map { "FAIL: \($0)" } ?? "PASS")
        exit(failure == nil ? 0 : 1)
    }
}
