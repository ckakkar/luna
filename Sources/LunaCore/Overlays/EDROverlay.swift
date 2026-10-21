import AppKit
import Metal
import MetalKit

/// XDR brightness beyond 100%: a click-through window over the whole screen that renders extended-range
/// "white" (a value above 1.0) and multiplies everything under it. macOS then drives the panel into its HDR
/// headroom, so ordinary content gets brighter. Technique as in levelsio/xdr-boost (MIT).
@MainActor
public final class EDROverlay: NSObject, MTKViewDelegate {
    private let window: ClickThroughWindow
    private let view: MTKView
    private let queue: MTLCommandQueue
    private var shown = false

    /// How much to multiply the screen by, 1… the display's headroom.
    public var multiplier: Double {
        didSet { updateClearColor() }
    }

    public init?(screen: NSScreen, multiplier: Double) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        self.multiplier = multiplier
        window = ClickThroughWindow(frame: screen.frame, level: .screenSaver)
        // Faded in once the first frame is up, so turning XDR on doesn't flash.
        window.alphaValue = 0
        view = MTKView(frame: NSRect(origin: .zero, size: screen.frame.size), device: device)
        super.init()

        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 5
        view.layer?.isOpaque = false
        if let layer = view.layer as? CAMetalLayer {
            layer.wantsExtendedDynamicRangeContent = true
        }
        view.layer?.compositingFilter = "multiply"
        view.delegate = self
        updateClearColor()

        window.contentView = view
        window.orderFrontRegardless()
    }

    public func move(to screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }

    public func close() {
        view.delegate = nil
        view.isPaused = true
        window.close()
    }

    private func updateClearColor() {
        let value = max(1, multiplier)
        view.clearColor = MTLClearColor(red: value, green: value, blue: value, alpha: 1)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
            let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
        if !shown {
            shown = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                window.animator().alphaValue = 1
            }
        }
    }
}

/// Keeps a display's HDR headroom open: a 1-point window showing extended-range white. Displays like a
/// MacBook Pro's open their headroom only while HDR content is on screen; this is that content, so XDR can
/// lift the colour table into it. It sits on the top edge, clear of a rounded corner.
@MainActor
public final class EDRTrigger: NSObject, MTKViewDelegate {
    private let window: ClickThroughWindow
    private let view: MTKView
    private let queue: MTLCommandQueue
    private let inset: CGFloat

    /// How bright the trigger's point is, which is how much headroom it asks for.
    public var value: Double {
        didSet {
            let v = max(1.05, value)
            view.clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: 1)
        }
    }

    public init?(screen: NSScreen, value: Double, avoidingCorner inset: CGFloat) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        self.inset = inset
        self.value = value
        window = ClickThroughWindow(
            frame: Self.frame(on: screen, inset: inset), level: NSWindow.Level(Int(CGShieldingWindowLevel())))
        window.sharingType = .none
        view = MTKView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), device: device)
        super.init()
        view.colorPixelFormat = .rgba16Float
        view.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        let v = max(1.05, value)
        view.clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: 1)
        view.preferredFramesPerSecond = 2
        view.delegate = self
        window.contentView = view
        window.orderFrontRegardless()
    }

    private static func frame(on screen: NSScreen, inset: CGFloat) -> NSRect {
        NSRect(x: screen.frame.minX + ceil(inset), y: screen.frame.maxY - 1, width: 1, height: 1)
    }

    public func move(to screen: NSScreen) {
        window.setFrame(Self.frame(on: screen, inset: inset), display: true)
        window.orderFrontRegardless()
    }

    public func close() {
        view.delegate = nil
        view.isPaused = true
        window.close()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
            let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
