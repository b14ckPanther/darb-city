import CoreLocation
import Observation

/// The person's position, while the app is in use. Darb asks only when the person asks for it,
/// uses the position on the phone to measure distances, and never sends or stores a trail of it.
@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Access: Sendable { case unasked, allowed, denied }

    private(set) var access: Access = .unasked
    private(set) var coordinate: Coordinate?
    /// Whether the phone is still looking for the first position.
    private(set) var isLocating = false
    /// Called when the permission or the position changes.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wanted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        access = Self.access(manager.authorizationStatus)
    }

    private static func access(_ s: CLAuthorizationStatus) -> Access {
        switch s {
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        case .denied, .restricted: .denied
        default: .unasked
        }
    }

    /// Starts following the position, asking for permission the first time.
    func start() {
        wanted = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isLocating = coordinate == nil
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func stop() {
        wanted = false
        isLocating = false
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.access = Self.access(status)
            if self.access == .allowed, self.wanted {
                self.isLocating = self.coordinate == nil
                self.manager.startUpdatingLocation()
            } else if self.access == .denied {
                self.isLocating = false
                self.coordinate = nil
            }
            self.onChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last, last.horizontalAccuracy >= 0 else { return }
        let c = Coordinate(lat: last.coordinate.latitude, lng: last.coordinate.longitude)
        Task { @MainActor in
            self.coordinate = c
            self.isLocating = false
            self.onChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.isLocating = false }
    }
}
