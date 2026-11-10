import AppKit

/// `--preview --snapshot <file.png>`: Luna saves a picture of its own window and quits, for design work and
/// the README. An app may always capture its own windows, so this needs no Screen Recording permission and
/// works from any terminal.
enum Snapshot {
    /// Waits `delay` seconds, captures, writes the PNG and quits (with exit code 1 if nothing was captured).
    static func schedule(to path: String, after delay: TimeInterval, target: @escaping @MainActor () -> Target?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let saved = target().flatMap { capture($0) }.map { write($0, to: path) } ?? false
                FileHandle.standardError.write(Data((saved ? "saved \(path)\n" : "no snapshot\n").utf8))
                exit(saved ? 0 : 1)
            }
        }
    }

    enum Target {
        /// One window on its own, with its shadowless frame.
        case window(NSWindow)
        /// Everything Luna shows from this window up, within its frame (the panel over the backdrop).
        case stack(above: NSWindow)
    }

    /// The window a snapshot means when none is named: the largest one showing.
    @MainActor static func largestWindow() -> NSWindow? {
        NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    // CGWindowListCreateImage is deprecated in favour of ScreenCaptureKit, which needs Screen Recording
    // permission even for an app's own windows; looked up at runtime so the build stays warning-free.
    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImage? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: CreateImage.self)
    }()

    @MainActor private static func capture(_ target: Target) -> CGImage? {
        guard let createImage else { return nil }
        // kCGWindowListOptionIncludingWindow 8, kCGWindowListOptionOnScreenAboveWindow 2;
        // kCGWindowImageBoundsIgnoreFraming 1, kCGWindowImageBestResolution 8.
        switch target {
        case let .window(window):
            return createImage(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue()
        case let .stack(window):
            // Quartz coordinates: from the top of the main screen, downwards.
            let height = NSScreen.screens.first?.frame.height ?? 0
            let frame = window.frame
            let rect = CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
            return createImage(rect, 2 | 8, UInt32(window.windowNumber), 8)?.takeRetainedValue()
        }
    }

    private static func write(_ image: CGImage, to path: String) -> Bool {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            return false
        }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
