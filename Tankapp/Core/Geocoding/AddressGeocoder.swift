import CoreLocation
import Foundation

enum GeocodingError: Error, LocalizedError, Equatable {
    case emptyAddress
    case notFound
    case cancelled
    case network(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .emptyAddress:
            return "Bitte eine Adresse eingeben."
        case .notFound:
            return "Adresse konnte nicht gefunden werden."
        case .cancelled:
            return "Suche wurde abgebrochen."
        case .network(let msg):
            return "Netzwerkfehler bei der Adress-Suche: \(msg)"
        case .failed(let msg):
            return "Adress-Suche fehlgeschlagen: \(msg)"
        }
    }
}

/// Abstraction über den konkreten Geocoding-Provider — ermöglicht in Tests,
/// `CLGeocoder` durch einen Fake zu ersetzen.
protocol GeocodingProvider {
    func geocode(_ address: String) async throws -> [CLPlacemark]
}

protocol Geocoding {
    func geocode(_ address: String) async throws -> CLLocation
}

final class AddressGeocoder: Geocoding {
    private let provider: GeocodingProvider

    init(provider: GeocodingProvider = CLGeocoderProvider()) {
        self.provider = provider
    }

    func geocode(_ address: String) async throws -> CLLocation {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GeocodingError.emptyAddress }

        let placemarks: [CLPlacemark]
        do {
            placemarks = try await provider.geocode(trimmed)
        } catch let error as GeocodingError {
            throw error
        } catch let error as CLError {
            throw Self.map(error)
        } catch {
            throw GeocodingError.failed(error.localizedDescription)
        }

        guard let location = placemarks.first?.location else {
            throw GeocodingError.notFound
        }
        return location
    }

    static func map(_ error: CLError) -> GeocodingError {
        switch error.code {
        case .geocodeFoundNoResult, .geocodeFoundPartialResult:
            return .notFound
        case .geocodeCanceled:
            return .cancelled
        case .network:
            return .network(error.localizedDescription)
        default:
            return .failed(error.localizedDescription)
        }
    }
}

struct CLGeocoderProvider: GeocodingProvider {
    func geocode(_ address: String) async throws -> [CLPlacemark] {
        try await CLGeocoder().geocodeAddressString(address)
    }
}
