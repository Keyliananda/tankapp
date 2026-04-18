import CoreLocation
import Foundation
import Observation

enum SortMode: String, CaseIterable, Identifiable, Hashable {
    case price
    case distance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .price: return "Preis"
        case .distance: return "Entfernung"
        }
    }
}

enum SearchState: Equatable {
    case idle
    case loading
    case results([Station])
    case empty
    case error(String)
}

/// Schmale Abstraktion über das, was das ViewModel vom Standort-Provider braucht.
/// Der konkrete `LocationManager` erfüllt das Protokoll via Extension.
@MainActor
protocol CurrentLocationProviding {
    func requestCurrentLocation() async throws -> CLLocation
}

extension LocationManager: CurrentLocationProviding {}

@MainActor
@Observable
final class SearchViewModel {
    // User-Input
    var query: String = ""
    var radiusKm: Double = 5
    var fuelType: FuelType = .e5
    var sortMode: SortMode = .price

    private(set) var state: SearchState = .idle

    private let client: TankerkoenigAPI
    private let location: CurrentLocationProviding
    private let geocoder: Geocoding

    init(
        client: TankerkoenigAPI,
        location: CurrentLocationProviding,
        geocoder: Geocoding
    ) {
        self.client = client
        self.location = location
        self.geocoder = geocoder
    }

    /// Führt die Suche aus. Nutzt die eingetippte Adresse, falls vorhanden — sonst den aktuellen Standort.
    /// Die Liste wird client-seitig nach `fuelType` / `sortMode` aufbereitet.
    func search() async {
        state = .loading

        let coordinate: CLLocationCoordinate2D
        do {
            coordinate = try await resolveCoordinate()
        } catch {
            state = .error(Self.message(for: error))
            return
        }

        let stations: [Station]
        do {
            stations = try await client.searchStations(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radiusKm: radiusKm
            )
        } catch {
            state = .error(Self.message(for: error))
            return
        }

        let processed = process(stations)
        state = processed.isEmpty ? .empty : .results(processed)
    }

    private func resolveCoordinate() async throws -> CLLocationCoordinate2D {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let loc = try await location.requestCurrentLocation()
            return loc.coordinate
        } else {
            let loc = try await geocoder.geocode(trimmed)
            return loc.coordinate
        }
    }

    private func process(_ stations: [Station]) -> [Station] {
        switch sortMode {
        case .price:
            return stations
                .filter { $0.price(for: fuelType) != nil }
                .sorted { lhs, rhs in
                    (lhs.price(for: fuelType) ?? .infinity) < (rhs.price(for: fuelType) ?? .infinity)
                }
        case .distance:
            return stations.sorted { $0.distanceKm < $1.distanceKm }
        }
    }

    private static func message(for error: Error) -> String {
        if let err = error as? LocalizedError, let description = err.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
