import CoreGraphics
import CoreLocation
import Foundation

/// Auto brightness. "Match Mac" follows the built-in display (which follows the room's light); "Sun"
/// follows daylight where you are. Either way, adjusting a display yourself teaches it: its curve learns
/// that point, so next time it lands where you like it.
@MainActor
public final class AutoBrightness {
    private unowned let controller: DisplayController
    private var timer: Timer?
    private var learnTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var location: LocationProvider?

    init(controller: DisplayController) {
        self.controller = controller
    }

    private var settings: AppSettings { controller.settings }

    /// Re-arms for the current mode and displays. Safe to call often.
    public func update() {
        timer?.invalidate()
        timer = nil
        guard !controller.isPreview else { return }

        switch settings.autoMode {
        case .off:
            break
        case .sync:
            // DisplayController observes the source and calls `sourceChanged`.
            if let source = controller.syncSource, let value = AppleNative.brightness(source.id) {
                follow(source: value)
            }
        case .sun:
            ensureLocation()
            followSun()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.followSun() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The display "Match Mac" follows changed brightness.
    func sourceChanged(_ value: Double) {
        guard settings.autoMode == .sync else { return }
        follow(source: value)
    }

    /// The input the curves map from right now: the source display's brightness, or daylight.
    public var currentInput: Double? {
        switch settings.autoMode {
        case .off: nil
        case .sync: controller.syncSource.flatMap { AppleNative.brightness($0.id) }
        case .sun: settings.location.map { Solar.daylight(at: Date(), latitude: $0.latitude, longitude: $0.longitude) }
        }
    }

    private func targets() -> [Display] {
        let source = settings.autoMode == .sync ? controller.syncSource : nil
        // A display pushed into XDR or dimmed below 0% was put there on purpose; leave it be.
        return controller.displays.filter { $0 !== source && $0.level.dim == 0 && $0.level.boost == 0 }
    }

    private func follow(source value: Double) {
        for display in targets() {
            display.animate(to: Level(brightness: display.settings.syncCurve.value(at: value)), duration: 0.5)
        }
    }

    private func followSun() {
        guard let daylight = currentInput else { return }
        for display in targets() {
            display.animate(to: Level(brightness: display.settings.sunCurve.value(at: daylight)), duration: 2.5)
        }
    }

    /// The user moved a slider: once they stop, remember where they put it for the current input.
    func userAdjusted(_ display: Display) {
        guard settings.autoMode != .off, display !== controller.syncSource || settings.autoMode == .sun else { return }
        learnTasks[display.id]?.cancel()
        learnTasks[display.id] = Task { [weak self, weak display] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, let self, let display, let input = self.currentInput,
                display.level.dim == 0, display.level.boost == 0
            else { return }
            switch self.settings.autoMode {
            case .sync: display.settings.syncCurve.learn(x: input, y: display.level.brightness)
            case .sun: display.settings.sunCurve.learn(x: input, y: display.level.brightness)
            case .off: break
            }
        }
    }

    // MARK: Location

    private func ensureLocation() {
        if settings.location == nil { settings.location = Self.approximateLocation() }
        if settings.location?.approximate == true { requestLocation() }
    }

    /// Asks macOS where the Mac is (once; it's remembered). Without permission Luna keeps the guess.
    public func requestLocation() {
        if location == nil { location = LocationProvider() }
        location?.request { [weak self] coordinate in
            guard let self, let coordinate else { return }
            self.settings.location = SavedLocation(
                latitude: coordinate.latitude, longitude: coordinate.longitude, approximate: false)
            if self.settings.autoMode == .sun { self.followSun() }
        }
    }

    /// A guess from the time zone: longitude from its offset, a temperate latitude in the right hemisphere.
    /// Good to within an hour or so of real sunrise and sunset.
    nonisolated public static func approximateLocation(timeZone: TimeZone = .current, date: Date = Date())
        -> SavedLocation
    {
        let standardOffset = Double(timeZone.secondsFromGMT(for: date)) - timeZone.daylightSavingTimeOffset(for: date)
        let longitude = (standardOffset / 3600 * 15).clamped(to: -180...180)
        let southern = [
            "Australia/", "Pacific/Auckland", "America/Argentina", "America/Sao_Paulo", "America/Santiago",
            "Africa/Johannesburg", "America/Montevideo", "Antarctica/",
        ]
        let latitude = southern.contains { timeZone.identifier.hasPrefix($0) } ? -34.0 : 40.0
        return SavedLocation(latitude: latitude, longitude: longitude, approximate: true)
    }
}

/// One-shot location lookup.
@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func request(_ completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: finish(nil)
        default: manager.requestLocation()
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        completion?(coordinate)
        completion = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .notDetermined: break
            case .denied, .restricted: self.finish(nil)
            default: self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
