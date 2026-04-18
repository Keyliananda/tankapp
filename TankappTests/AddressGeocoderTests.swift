import CoreLocation
import MapKit
import XCTest
@testable import Tankapp

final class AddressGeocoderTests: XCTestCase {

    // MARK: - Happy path

    func test_geocode_returnsFirstPlacemarksLocation() async throws {
        let expected = CLLocation(latitude: 52.034, longitude: 8.534)
        let stub = StubGeocodingProvider(result: .success([
            FakePlacemark.make(location: expected),
            FakePlacemark.make(location: CLLocation(latitude: 0, longitude: 0))
        ]))
        let sut = AddressGeocoder(provider: stub)

        let location = try await sut.geocode("Hauptstr. 12, Bielefeld")

        XCTAssertEqual(location.coordinate.latitude, 52.034, accuracy: 0.0001)
        XCTAssertEqual(location.coordinate.longitude, 8.534, accuracy: 0.0001)
    }

    func test_geocode_trimsWhitespaceBeforeForwarding() async throws {
        let stub = StubGeocodingProvider(result: .success([
            FakePlacemark.make(location: CLLocation(latitude: 1, longitude: 2))
        ]))
        let sut = AddressGeocoder(provider: stub)

        _ = try await sut.geocode("   Berlin  \n")

        XCTAssertEqual(stub.receivedAddress, "Berlin")
    }

    // MARK: - Input validation

    func test_geocode_throwsEmptyAddress_forBlankInput() async {
        let stub = StubGeocodingProvider(result: .success([]))
        let sut = AddressGeocoder(provider: stub)

        await assertThrows(GeocodingError.emptyAddress) {
            _ = try await sut.geocode("   \n\t  ")
        }
        XCTAssertNil(stub.receivedAddress, "Provider darf bei leerer Eingabe nicht aufgerufen werden.")
    }

    func test_geocode_throwsEmptyAddress_forEmptyString() async {
        let stub = StubGeocodingProvider(result: .success([]))
        let sut = AddressGeocoder(provider: stub)

        await assertThrows(GeocodingError.emptyAddress) {
            _ = try await sut.geocode("")
        }
    }

    // MARK: - Not found

    func test_geocode_throwsNotFound_whenProviderReturnsEmpty() async {
        let stub = StubGeocodingProvider(result: .success([]))
        let sut = AddressGeocoder(provider: stub)

        await assertThrows(GeocodingError.notFound) {
            _ = try await sut.geocode("Nichtexistent")
        }
    }

    func test_geocode_throwsNotFound_whenFirstPlacemarkHasNoLocation() async {
        let stub = StubGeocodingProvider(result: .success([
            FakePlacemark.make(location: nil)
        ]))
        let sut = AddressGeocoder(provider: stub)

        await assertThrows(GeocodingError.notFound) {
            _ = try await sut.geocode("Irgendwo")
        }
    }

    // MARK: - CLError mapping

    func test_map_geocodeFoundNoResult_toNotFound() {
        let err = CLError(.geocodeFoundNoResult)
        XCTAssertEqual(AddressGeocoder.map(err), .notFound)
    }

    func test_map_geocodeFoundPartialResult_toNotFound() {
        let err = CLError(.geocodeFoundPartialResult)
        XCTAssertEqual(AddressGeocoder.map(err), .notFound)
    }

    func test_map_geocodeCanceled_toCancelled() {
        let err = CLError(.geocodeCanceled)
        XCTAssertEqual(AddressGeocoder.map(err), .cancelled)
    }

    func test_map_network_toNetwork() {
        let err = CLError(.network)
        if case .network = AddressGeocoder.map(err) { return }
        XCTFail("Expected .network case")
    }

    func test_map_unknownCode_toFailed() {
        let err = CLError(.denied)
        if case .failed = AddressGeocoder.map(err) { return }
        XCTFail("Expected .failed case")
    }

    // MARK: - Provider errors bubble up through mapping

    func test_geocode_mapsCLError_fromProvider() async {
        let stub = StubGeocodingProvider(result: .failure(CLError(.geocodeFoundNoResult)))
        let sut = AddressGeocoder(provider: stub)

        await assertThrows(GeocodingError.notFound) {
            _ = try await sut.geocode("Atlantis")
        }
    }

    func test_geocode_wrapsUnknownError_asFailed() async {
        struct OddError: Error {}
        let stub = StubGeocodingProvider(result: .failure(OddError()))
        let sut = AddressGeocoder(provider: stub)

        do {
            _ = try await sut.geocode("X")
            XCTFail("Expected error")
        } catch let error as GeocodingError {
            if case .failed = error { return }
            XCTFail("Expected .failed, got \(error)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: GeocodingError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
            XCTFail("Expected error \(expected)", file: file, line: line)
        } catch let error as GeocodingError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

// MARK: - Test doubles

private final class StubGeocodingProvider: GeocodingProvider, @unchecked Sendable {
    private let result: Result<[CLPlacemark], Error>
    private(set) var receivedAddress: String?

    init(result: Result<[CLPlacemark], Error>) {
        self.result = result
    }

    func geocode(_ address: String) async throws -> [CLPlacemark] {
        receivedAddress = address
        switch result {
        case .success(let placemarks): return placemarks
        case .failure(let error): throw error
        }
    }
}

/// `CLPlacemark`'s Standard-Init ist in iOS nicht verfügbar.
/// `MKPlacemark` erbt von `CLPlacemark`, akzeptiert eine Koordinate und liefert `location` daraus.
/// Für den "kein Standort"-Fall verwenden wir eine ungültige Koordinate (NaN) und
/// prüfen das in `FakePlacemark.make`, indem wir die location-Eigenschaft via Subklasse blockieren.
private enum FakePlacemark {
    static func make(location: CLLocation?) -> CLPlacemark {
        if let location {
            return MKPlacemark(coordinate: location.coordinate)
        }
        return NoLocationPlacemark(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0))
    }
}

/// `MKPlacemark`-Subklasse, die `location` auf `nil` zwingt — simuliert einen Placemark
/// ohne Koordinate (z.B. Teilergebnis von CLGeocoder).
private final class NoLocationPlacemark: MKPlacemark, @unchecked Sendable {
    override var location: CLLocation? { nil }
}
