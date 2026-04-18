import CoreLocation
import Foundation
import Observation

enum LocationAuthorizationStatus: Equatable {
    case notDetermined
    case restricted
    case denied
    case authorizedWhenInUse
    case authorizedAlways

    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorizedAlways: self = .authorizedAlways
        case .authorizedWhenInUse: self = .authorizedWhenInUse
        @unknown default: self = .denied
        }
    }

    var isAuthorized: Bool {
        self == .authorizedWhenInUse || self == .authorizedAlways
    }
}

enum LocationError: Error, LocalizedError, Equatable {
    case permissionDenied
    case permissionRestricted
    case permissionPending
    case locationUnknown
    case network(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Standortzugriff wurde verweigert. Bitte in den Einstellungen erlauben."
        case .permissionRestricted:
            return "Standortzugriff ist auf diesem Gerät eingeschränkt."
        case .permissionPending:
            return "Standortzugriff noch nicht erteilt."
        case .locationUnknown:
            return "Standort konnte aktuell nicht bestimmt werden."
        case .network(let msg):
            return "Netzwerkfehler bei der Standortbestimmung: \(msg)"
        case .failed(let msg):
            return "Standortbestimmung fehlgeschlagen: \(msg)"
        }
    }

    static func from(_ error: CLError) -> LocationError {
        switch error.code {
        case .denied: return .permissionDenied
        case .locationUnknown: return .locationUnknown
        case .network: return .network(error.localizedDescription)
        default: return .failed(error.localizedDescription)
        }
    }
}

/// Abstraction über `CLLocationManager` — nur die Teile, die der `LocationManager` braucht.
/// Erlaubt in Tests den Austausch durch einen Fake ohne Permission-Dialog.
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var delegate: CLLocationManagerDelegate? { get set }
    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: LocationProviding {}

@MainActor
@Observable
final class LocationManager: NSObject {
    private(set) var authorizationStatus: LocationAuthorizationStatus
    private(set) var lastLocation: CLLocation?

    private let provider: LocationProviding
    private var pendingContinuations: [CheckedContinuation<CLLocation, Error>] = []

    init(provider: LocationProviding = CLLocationManager()) {
        self.provider = provider
        self.authorizationStatus = LocationAuthorizationStatus(provider.authorizationStatus)
        super.init()
        self.provider.delegate = self
    }

    func requestAuthorization() {
        guard authorizationStatus == .notDetermined else { return }
        provider.requestWhenInUseAuthorization()
    }

    func requestCurrentLocation() async throws -> CLLocation {
        switch authorizationStatus {
        case .denied:
            throw LocationError.permissionDenied
        case .restricted:
            throw LocationError.permissionRestricted
        case .notDetermined:
            throw LocationError.permissionPending
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations.append(continuation)
            provider.requestLocation()
        }
    }

    // MARK: - Delegate shim (also called directly from tests)

    func deliverAuthorizationStatus(_ status: CLAuthorizationStatus) {
        authorizationStatus = LocationAuthorizationStatus(status)
    }

    func deliverLocation(_ location: CLLocation) {
        lastLocation = location
        let pending = pendingContinuations
        pendingContinuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: location)
        }
    }

    func deliverError(_ error: Error) {
        let mapped: LocationError
        if let clError = error as? CLError {
            mapped = LocationError.from(clError)
        } else {
            mapped = LocationError.failed(error.localizedDescription)
        }
        let pending = pendingContinuations
        pendingContinuations.removeAll()
        for continuation in pending {
            continuation.resume(throwing: mapped)
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.deliverAuthorizationStatus(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.deliverLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.deliverError(error)
        }
    }
}
