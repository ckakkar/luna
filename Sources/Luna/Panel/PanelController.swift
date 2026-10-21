import AppKit
import LunaCore
import SwiftUI

/// The menu bar icon and the panel that drops from it. A custom panel rather than `MenuBarExtra` so it can
/// be glass edge to edge, animate, open from code and stay up for `--preview`.
final class PanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = LunaPanel()
    private let hosting: NSHostingController<AnyView>
    private var sizeObservation: NSKeyValueObservation?
    private var monitors: [Any] = []
    private var glyphPhase = -1.0
    /// The panel content's size, as SwiftUI last reported it.
    private var contentSize = NSSize(width: Metrics.panelWidth + 2 * Metrics.panelMargin, height: 300)
    /// Stays open whatever is clicked (preview and screenshots).
    var pinned = false

    init(model: AppModel) {
        self.model = model
        hosting = NSHostingController(
            rootView: AnyView(PanelView().environment(model).focusEffectDisabled().padding(Metrics.panelMargin)))
        super.init()

        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting.view
        // Size changes are reported on the main thread, where the hosting controller lives.
        sizeObservation = hosting.observe(\.preferredContentSize, options: [.initial, .new]) { [weak self] hosting, _ in
            MainActor.assumeIsolated {
                let size = hosting.preferredContentSize
                DispatchQueue.main.async { self?.resize(to: size) }
            }
        }
        panel.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Luna")
        }
        updateGlyph()
    }

    var isShown: Bool { panel.isVisible }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            PopUpMenu.show([
                .init(title: "Settings…", symbol: "gearshape") { [model] in model.openSettings(.general) },
                .separator,
                .init(title: "Quit Luna", symbol: "power") { [model] in model.quit() },
            ])
            return
        }
        toggle()
    }

    func toggle() {
        isShown ? hide() : show()
    }

    func show(centeredOn screen: NSScreen? = nil) {
        guard !isShown else { return }
        let fitting = hosting.sizeThatFits(
            in: CGSize(width: Metrics.panelWidth + 2 * Metrics.panelMargin, height: 4000))
        if fitting.width > 0, fitting.height > 0 { contentSize = fitting }
        let size = contentSize
        let frame: NSRect
        if let screen {
            frame = NSRect(
                x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                width: size.width, height: size.height)
        } else {
            frame = frameBelowStatusItem(size: size)
        }
        panel.setFrame(frame, display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        statusItem.button?.highlight(true)
        installMonitors()
    }

    func hide() {
        guard isShown, !pinned else { return }
        removeMonitors()
        statusItem.button?.highlight(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    /// The menu bar moon fills with the brightness of the display under the pointer.
    func updateGlyph() {
        let display = model.controller.displayUnderPointer
        let phase = display?.position ?? 0.6
        guard abs(phase - glyphPhase) > 0.02 else { return }
        glyphPhase = phase
        statusItem.button?.image = MoonGlyph.menuBarImage(brightness: phase)
    }

    private func frameBelowStatusItem(size: NSSize) -> NSRect {
        guard let button = statusItem.button, let window = button.window else {
            let screen = NSScreen.main?.visibleFrame ?? .zero
            return NSRect(
                x: screen.maxX - size.width - 8 + Metrics.panelMargin,
                y: screen.maxY - size.height - 6 + Metrics.panelMargin, width: size.width, height: size.height)
        }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? anchor
        // Place the glass itself (inside the margin) 6 pt under the menu bar and 8 pt from the screen's edges.
        let margin = Metrics.panelMargin
        let x = min(
            max(anchor.midX - size.width / 2, visible.minX + 8 - margin), visible.maxX - size.width - 8 + margin)
        return NSRect(x: x, y: anchor.minY - size.height - 6 + margin, width: size.width, height: size.height)
    }

    /// Keeps the top edge in place as the content grows or shrinks.
    private func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        contentSize = size
        var frame = panel.frame
        guard frame.size != size else { return }
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true)
    }

    private func installMonitors() {
        removeMonitors()
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            })
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                guard event.keyCode == 53 else { return event }  // Esc
                MainActor.assumeIsolated { self?.hide() }
                return nil
            })
        {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Another of Luna's windows (Settings) took over.
        if NSApp.keyWindow != nil, NSApp.keyWindow !== panel { hide() }
    }
}

/// A borderless, transparent panel that floats over everything without taking focus from the app you're in.
final class LunaPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 300),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own edge; a window shadow would trace the window's rectangle.
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}
