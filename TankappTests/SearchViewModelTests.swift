import CoreLocation
import XCTest
@testable import Tankapp

@MainActor
final class SearchViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let sut = makeSUT()
        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(sut.fuelType, .e5)
        XCTAssertEqual(sut.sortMode, .price)
        XCTAssertEqual(sut.radiusKm, 5)
        XCTAssertEqual(sut.query, "")
    }

    // MARK: - Location vs. address path

    func test_search_usesCurrentLocation_whenQueryIsEmpty() async {
        let client = StubClient(result: .success([]))
        let location = StubLocation(result: .success(CLLocation(latitude: 52.5, longitude: 13.4)))
        let geocoder = StubGeocoder(result: .success(CLLocation(latitude: 0, longitude: 0)))
        let sut = makeSUT(client: client, location: location, geocoder: geocoder)

        await sut.search()

        XCTAssertEqual(location.callCount, 1)
        XCTAssertEqual(geocoder.callCount, 0)
    }

    func test_search_usesCurrentLocation_whenQueryIsBlank() async {
        let client = StubClient(result: .success([]))
        let location = StubLocation(result: .success(CLLocation(latitude: 52.5, longitude: 13.4)))
        let geocoder = StubGeocoder(result: .success(CLLocation(latitude: 0, longitude: 0)))
        let sut = makeSUT(client: client, location: location, geocoder: geocoder)
        sut.query = "   \n\t "

        await sut.search()

        XCTAssertEqual(location.callCount, 1)
        XCTAssertEqual(geocoder.callCount, 0)
    }

    func test_search_geocodesAddress_whenQueryHasContent() async {
        let client = StubClient(result: .success([]))
        let location = StubLocation(result: .success(CLLocation(latitude: 0, longitude: 0)))
        let geocoder = StubGeocoder(result: .success(CLLocation(latitude: 48.1, longitude: 11.6)))
        let sut = makeSUT(client: client, location: location, geocoder: geocoder)
        sut.query = "  Marienplatz, München  "

        await sut.search()

        XCTAssertEqual(geocoder.callCount, 1)
        XCTAssertEqual(geocoder.receivedAddress, "  Marienplatz, München  ",
                       "Geocoder macht sein eigenes Trimming — VM reicht den Originalstring weiter")
        XCTAssertEqual(location.callCount, 0)
    }

    // MARK: - Client-Aufruf

    func test_search_forwardsResolvedCoordinateAndRadiusToClient() async {
        let client = StubClient(result: .success([]))
        let location = StubLocation(result: .success(CLLocation(latitude: 52.034, longitude: 8.534)))
        let sut = makeSUT(client: client, location: location)
        sut.radiusKm = 12

        await sut.search()

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.receivedLatitude, 52.034)
        XCTAssertEqual(client.receivedLongitude, 8.534)
        XCTAssertEqual(client.receivedRadius, 12)
    }

    // MARK: - Results / Empty

    func test_search_setsEmpty_whenClientReturnsNoStations() async {
        let sut = makeSUT(client: StubClient(result: .success([])))
        await sut.search()
        XCTAssertEqual(sut.state, .empty)
    }

    func test_search_setsResults_whenClientReturnsStations() async {
        let stations = [
            makeStation(id: "a", distanceKm: 1, prices: [.e5: 1.799]),
            makeStation(id: "b", distanceKm: 2, prices: [.e5: 1.599])
        ]
        let sut = makeSUT(client: StubClient(result: .success(stations)))

        await sut.search()

        guard case .results(let out) = sut.state else {
            return XCTFail("Expected .results, got \(sut.state)")
        }
        XCTAssertEqual(out.count, 2)
    }

    // MARK: - Sort: price

    func test_search_sortByPrice_ordersAscending_forSelectedFuelType() async {
        let stations = [
            makeStation(id: "a", distanceKm: 3, prices: [.e5: 1.899]),
            makeStation(id: "b", distanceKm: 1, prices: [.e5: 1.599]),
            makeStation(id: "c", distanceKm: 2, prices: [.e5: 1.699])
        ]
        let sut = makeSUT(client: StubClient(result: .success(stations)))
        sut.sortMode = .price
        sut.fuelType = .e5

        await sut.search()

        let ids = extractResultIDs(sut.state)
        XCTAssertEqual(ids, ["b", "c", "a"])
    }

    func test_search_sortByPrice_filtersOutStationsWithoutSelectedFuelType() async {
        let stations = [
            makeStation(id: "a", distanceKm: 1, prices: [.e5: 1.799]),
            makeStation(id: "b", distanceKm: 2, prices: [.diesel: 1.599]), // fehlt e5
            makeStation(id: "c", distanceKm: 3, prices: [.e5: 1.699])
        ]
        let sut = makeSUT(client: StubClient(result: .success(stations)))
        sut.sortMode = .price
        sut.fuelType = .e5

        await sut.search()

        XCTAssertEqual(extractResultIDs(sut.state), ["c", "a"])
    }

    func test_search_setsEmpty_whenPriceSort_filtersOutAll() async {
        let stations = [
            makeStation(id: "a", distanceKm: 1, prices: [.diesel: 1.5]),
            makeStation(id: "b", distanceKm: 2, prices: [.diesel: 1.6])
        ]
        let sut = makeSUT(client: StubClient(result: .success(stations)))
        sut.sortMode = .price
        sut.fuelType = .e5

        await sut.search()

        XCTAssertEqual(sut.state, .empty)
    }

    func test_search_fuelTypeChange_altersPriceSortOrder() async {
        let stations = [
            makeStation(id: "a", distanceKm: 0, prices: [.e5: 1.8, .diesel: 1.4]),
            makeStation(id: "b", distanceKm: 0, prices: [.e5: 1.6, .diesel: 1.5])
        ]
        let sut = makeSUT(client: StubClient(result: .success(stations)))
        sut.sortMode = .price

        sut.fuelType = .e5
        await sut.search()
        XCTAssertEqual(extractResultIDs(sut.state), ["b", "a"])

        sut.fuelType = .diesel
        await sut.search()
        XCTAssertEqual(extractResultIDs(sut.state), ["a", "b"])
    }

    // MARK: - Sort: distance

    func test_search_sortByDistance_ordersAscending_andKeepsStationsWithoutSelectedFuelType() async {
        let stations = [
            makeStation(id: "a", distanceKm: 5, prices: [.e5: 1.5]),
            makeStation(id: "b", distanceKm: 1, prices: [.diesel: 1.5]), // kein e5
            makeStation(id: "c", distanceKm: 3, prices: [.e5: 1.7])
        ]
        let sut = makeSUT(client: StubClient(result: .success(stations)))
        sut.sortMode = .distance
        sut.fuelType = .e5

        await sut.search()

        XCTAssertEqual(extractResultIDs(sut.state), ["b", "c", "a"])
    }

    // MARK: - Errors

    func test_search_setsError_onLocationFailure_withLocalizedMessage() async {
        let location = StubLocation(result: .failure(LocationError.permissionDenied))
        let sut = makeSUT(
            client: StubClient(result: .success([])),
            location: location
        )

        await sut.search()

        guard case .error(let msg) = sut.state else {
            return XCTFail("Expected .error, got \(sut.state)")
        }
        XCTAssertEqual(msg, LocationError.permissionDenied.errorDescription)
    }

    func test_search_setsError_onGeocodingFailure_withLocalizedMessage() async {
        let geocoder = StubGeocoder(result: .failure(GeocodingError.notFound))
        let sut = makeSUT(
            client: StubClient(result: .success([])),
            geocoder: geocoder
        )
        sut.query = "Atlantis"

        await sut.search()

        guard case .error(let msg) = sut.state else {
            return XCTFail("Expected .error, got \(sut.state)")
        }
        XCTAssertEqual(msg, GeocodingError.notFound.errorDescription)
    }

    func test_search_setsError_onAPIFailure_withLocalizedMessage() async {
        let client = StubClient(result: .failure(APIError.apiError("apikey nicht gefunden")))
        let sut = makeSUT(client: client)

        await sut.search()

        guard case .error(let msg) = sut.state else {
            return XCTFail("Expected .error, got \(sut.state)")
        }
        XCTAssertEqual(msg, APIError.apiError("apikey nicht gefunden").errorDescription)
    }

    func test_search_doesNotCallClient_whenLocationResolutionFails() async {
        let client = StubClient(result: .success([]))
        let location = StubLocation(result: .failure(LocationError.permissionDenied))
        let sut = makeSUT(client: client, location: location)

        await sut.search()

        XCTAssertEqual(client.callCount, 0)
    }

    // MARK: - Loading-State

    func test_search_setsLoadingState_whileClientIsInFlight() async {
        let client = ControllableClient()
        let sut = makeSUT(client: client)

        let task = Task { await sut.search() }
        await waitUntilTrue { client.invocations == 1 }

        XCTAssertEqual(sut.state, .loading)

        client.finish(with: .success([]))
        await task.value
        XCTAssertEqual(sut.state, .empty)
    }

    // MARK: - Helpers

    private func makeSUT(
        client: TankerkoenigAPI? = nil,
        location: CurrentLocationProviding? = nil,
        geocoder: Geocoding? = nil
    ) -> SearchViewModel {
        SearchViewModel(
            client: client ?? StubClient(result: .success([])),
            location: location ?? StubLocation(result: .success(CLLocation(latitude: 0, longitude: 0))),
            geocoder: geocoder ?? StubGeocoder(result: .success(CLLocation(latitude: 0, longitude: 0)))
        )
    }

    private func makeStation(
        id: String,
        distanceKm: Double,
        prices: [FuelType: Double]
    ) -> Station {
        Station(
            id: id,
            name: "Station \(id)",
            brand: "Brand \(id)",
            street: "Teststr.",
            houseNumber: "1",
            postCode: 12345,
            place: "Testort",
            latitude: 0,
            longitude: 0,
            distanceKm: distanceKm,
            isOpen: true,
            prices: prices
        )
    }

    private func extractResultIDs(_ state: SearchState) -> [String] {
        guard case .results(let stations) = state else { return [] }
        return stations.map(\.id)
    }

    private func waitUntilTrue(
        timeout: TimeInterval = 1.0,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

// MARK: - Test doubles

private final class StubClient: TankerkoenigAPI, @unchecked Sendable {
    private let result: Result<[Station], Error>
    private(set) var callCount = 0
    private(set) var receivedLatitude: Double?
    private(set) var receivedLongitude: Double?
    private(set) var receivedRadius: Double?

    init(result: Result<[Station], Error>) {
        self.result = result
    }

    func searchStations(
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) async throws -> [Station] {
        callCount += 1
        receivedLatitude = latitude
        receivedLongitude = longitude
        receivedRadius = radiusKm
        switch result {
        case .success(let stations): return stations
        case .failure(let error): throw error
        }
    }
}

/// Erlaubt dem Test, das Erfüllen der `searchStations`-Anfrage manuell auszulösen,
/// damit wir den `.loading`-Zwischenzustand beobachten können.
private final class ControllableClient: TankerkoenigAPI, @unchecked Sendable {
    private var continuation: CheckedContinuation<[Station], Error>?
    private(set) var invocations = 0

    func searchStations(
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) async throws -> [Station] {
        invocations += 1
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
        }
    }

    func finish(with result: Result<[Station], Error>) {
        let cont = continuation
        continuation = nil
        switch result {
        case .success(let stations): cont?.resume(returning: stations)
        case .failure(let error): cont?.resume(throwing: error)
        }
    }
}

@MainActor
private final class StubLocation: CurrentLocationProviding {
    private let result: Result<CLLocation, Error>
    private(set) var callCount = 0

    init(result: Result<CLLocation, Error>) {
        self.result = result
    }

    func requestCurrentLocation() async throws -> CLLocation {
        callCount += 1
        switch result {
        case .success(let location): return location
        case .failure(let error): throw error
        }
    }
}

private final class StubGeocoder: Geocoding, @unchecked Sendable {
    private let result: Result<CLLocation, Error>
    private(set) var callCount = 0
    private(set) var receivedAddress: String?

    init(result: Result<CLLocation, Error>) {
        self.result = result
    }

    func geocode(_ address: String) async throws -> CLLocation {
        callCount += 1
        receivedAddress = address
        switch result {
        case .success(let location): return location
        case .failure(let error): throw error
        }
    }
}
