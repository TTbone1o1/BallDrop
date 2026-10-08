import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var location: CLLocation?
    private(set) var lastKnownLocation: CLLocation?
    private(set) var isTemporarilyUnavailable = false

    private static let savedLocationKey = "BallDrop.lastLocation"
    private let manager: CLLocationManager
    private let defaults: UserDefaults
    private var isActive = false

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    init(defaults: UserDefaults = .standard, manager: CLLocationManager = CLLocationManager()) {
        self.defaults = defaults
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        lastKnownLocation = Self.readSavedLocation(from: defaults)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    func setActive(_ active: Bool) {
        isActive = active
        authorizationStatus = manager.authorizationStatus

        guard active else {
            manager.stopUpdatingLocation()
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            location = nil
            manager.stopUpdatingLocation()
        @unknown default:
            manager.stopUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized && isActive {
            manager.startUpdatingLocation()
        } else if !isAuthorized {
            location = nil
            isTemporarilyUnavailable = false
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isActive, isAuthorized else { return }
        let now = Date()
        guard let latest = locations.filter({
            Self.isValid($0) && (0..<60).contains(now.timeIntervalSince($0.timestamp))
        }).max(by: { $0.timestamp < $1.timestamp }) else { return }

        // CoreLocation may deliver a cached or out-of-order fix. Never replace
        // a newer successful fix with an older one.
        if let lastKnownLocation, latest.timestamp <= lastKnownLocation.timestamp { return }
        location = latest
        lastKnownLocation = latest
        isTemporarilyUnavailable = false
        defaults.set([
            "latitude": latest.coordinate.latitude,
            "longitude": latest.coordinate.longitude,
            "accuracy": latest.horizontalAccuracy,
            "timestamp": latest.timestamp.timeIntervalSince1970
        ], forKey: Self.savedLocationKey)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A temporary loss of GPS keeps the last useful location and retries naturally.
        isTemporarilyUnavailable = true
        if (error as? CLError)?.code == .denied {
            authorizationStatus = manager.authorizationStatus
            location = nil
            manager.stopUpdatingLocation()
        }
    }

    private static func isValid(_ location: CLLocation) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy.isFinite
            && location.horizontalAccuracy >= 0
            && location.timestamp.timeIntervalSince1970.isFinite
    }

    private static func readSavedLocation(from defaults: UserDefaults) -> CLLocation? {
        guard let saved = defaults.dictionary(forKey: savedLocationKey),
              let latitude = saved["latitude"] as? Double,
              let longitude = saved["longitude"] as? Double,
              let accuracy = saved["accuracy"] as? Double,
              let timestamp = saved["timestamp"] as? Double,
              timestamp.isFinite, timestamp <= Date().timeIntervalSince1970 else { return nil }

        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
        // Old fixes remain useful as a starting map position, never as a live fix.
        return isValid(location) ? location : nil
    }
}
