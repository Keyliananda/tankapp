import CoreLocation
import XCTest
@testable import Tankapp

@MainActor
final class LocationManagerTests: XCTestCase {

    // MARK: - Authorization status mapping

    func test_authorizationStatus_mapsAllCases() {
        XCTAssertEqual(LocationAuthorizationStatus(.notDetermined), .notDetermined)
        XCTAssertEqual(LocationAuthorizationStatus(.restricted), .restricted)
        XCTAssertEqual(LocationAuthorizationStatus(.denied), .denied)
        XCTAssertEqual(LocationAuthorizationStatus(.authorizedAlways), .authorizedAlways)
        XCTAssertEqual(LocationAuthorizationStatus(.authorizedWhenInUse), .authorizedWhenInUse)
    }

    func test_isAuthorized_onlyForWhenInUseAndAlways() {
        XCTAssertTrue(LocationAuthorizationStatus.authorizedWhenInUse.isAuthorized)
        XCTAssertTrue(LocationAuthorizationStatus.authorizedAlways.isAuthorized)
        XCTAssertFalse(LocationAuthorizationStatus.notDetermined.isAuthorized)
        XCTAssertFalse(LocationAuthorizationStatus.denied.isAuthorized)
        XCTAssertFalse(LocationAuthorizationStatus.restricted.isAuthorized)
    }

    // MARK: - Error mapping

    func test_locationError_fromCLError_denied() {
        XCTAssertEqual(LocationError.from(CLError(.denied)), .permissionDenied)
    }

    func test_locationError_fromCLError_locationUnknown() {
        XCTAssertEqual(LocationError.from(CLError(.locationUnknown)), .locationUnknown)
    }

    func test_locationError_fromCLError_network() {
        if case .network = LocationError.from(CLError(.network)) { return }
        XCTFail("Expected .network mapping")
    }

    func test_locationError_fromCLError_fallbackFailed() {
        if case .failed = LocationError.from(CLError(.headingFailure)) { return }
        XCTFail("Expected .failed mapping for unknown codes")
    }

    // MARK: - Init

    func test_init_adoptsProviderAuthorizationStatus() {
        let provider = FakeLocationProvider(authorizationStatus: .authorizedWhenInUse)
        let sut = LocationManager(provider: provider)

        XCTAssertEqual(sut.authorizationStatus, .authorizedWhenInUse)
        XCTAssertTrue(provider.delegate === sut, "Provider-Delegate muss der Manager sein")
    }

    // MARK: - requestAuthorization

    func test_requestAuthorization_callsProvider_whenNotDetermined() {
        let provider = FakeLocationProvider(authorizationStatus: .notDetermined)
        let sut = LocationManager(provider: provider)

        sut.requestAuthorization()

        XCTAssertEqual(provider.requestWhenInUseCallCount, 1)
    }

    func test_requestAuthorization_doesNotCallProvider_whenAlreadyDenied() {
        let provider = FakeLocationProvider(authorizationStatus: .denied)
        let sut = LocationManager(provider: provider)

        sut.requestAuthorization()

        XCTAssertEqual(provider.requestWhenInUseCallCount, 0)
    }

    func test_requestAuthorization_doesNotCallProvider_whenAlreadyAuthorized() {
        let provider = FakeLocationProvider(authorizationStatus: .authorizedWhenInUse)
        let sut = LocationManager(provider: provider)

        sut.requestAuthorization()

        XCTAssertEqual(provider.requestWhenInUseCallCount, 0)
    }

    // MARK: - requestCurrentLocation preconditions

    func test_requestCurrentLocation_throwsPermissionDenied_whenDenied() async {
        let provider = FakeLocationProvider(authorizationStatus: .denied)
        let sut = LocationManager(provider: provider)

        await assertThrows(LocationError.permissionDenied) {
            _ = try await sut.requestCurrentLocation()
        }
        XCTAssertEqual(provider.requestLocationCallCount, 0)
    }

    func test_requestCurrentLocation_throwsPermissionRestricted_whenRestricted() async {
        let provider = FakeLocationProvider(authorizationStatus: .restricted)
        let sut = LocationManager(provider: provider)

        await assertThrows(LocationError.permissionRestricted) {
            _ = try await sut.requestCurrentLocation()
        }
    }

    func test_requestCurrentLocation_throwsPermissionPending_whenNotDetermined() async {
        let provider = FakeLocationProvider(authorizationStatus: .notDetermined)
        let sut = LocationManager(provider: provider)

        await assertThrows(LocationError.permissionPending) {
            _ = try await sut.requestCurrentLocation()
        }
    }

    // MARK: - requestCurrentLocation flow

    func test_requestCurrentLocation_resumesWithLocation_onDelivery() async throws {
        let provider = FakeLocationProvider(authorizationStatus: .authorizedWhenInUse)
        let sut = LocationManager(provider: provider)
        let expected = CLLocation(latitude: 52.51, longitude: 13.4)

        async let result = sut.requestCurrentLocation()
        await waitUntilTrue { provider.requestLocationCallCount == 1 }
        sut.deliverLocation(expected)

        let location = try await result
        XCTAssertEqual(location.coordinate.latitude, 52.51, accuracy: 0.0001)
        XCTAssertEqual(location.coordinate.longitude, 13.4, accuracy: 0.0001)
        let last = try XCTUnwrap(sut.lastLocation)
        XCTAssertEqual(last.coordinate.latitude, 52.51, accuracy: 0.0001)
    }

    func test_requestCurrentLocation_throwsMappedError_onDelegateFailure() async {
        let provider = FakeLocationProvider(authorizationStatus: .authorizedWhenInUse)
        let sut = LocationManager(provider: provider)

        async let result: CLLocation = sut.requestCurrentLocation()
        await waitUntilTrue { provider.requestLocationCallCount == 1 }
        sut.deliverError(CLError(.denied))

        do {
            _ = try await result
            XCTFail("Expected permissionDenied")
        } catch let error as LocationError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_deliverLocation_resumesAllPendingWaiters() async throws {
        let provider = FakeLocationProvider(authorizationStatus: .authorizedWhenInUse)
        let sut = LocationManager(provider: provider)
        let expected = CLLocation(latitude: 1, longitude: 2)

        async let first = sut.requestCurrentLocation()
        async let second = sut.requestCurrentLocation()
        await waitUntilTrue { provider.requestLocationCallCount >= 2 }
        sut.deliverLocation(expected)

        let a = try await first
        let b = try await second
        XCTAssertEqual(a.coordinate.latitude, 1, accuracy: 0.0001)
        XCTAssertEqual(b.coordinate.latitude, 1, accuracy: 0.0001)
    }

    func test_deliverAuthorizationStatus_updatesObservableProperty() {
        let provider = FakeLocationProvider(authorizationStatus: .notDetermined)
        let sut = LocationManager(provider: provider)

        sut.deliverAuthorizationStatus(.authorizedWhenInUse)

        XCTAssertEqual(sut.authorizationStatus, .authorizedWhenInUse)
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: LocationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async {
        do {
            try await block()
            XCTFail("Expected error \(expected)", file: file, line: line)
        } catch let error as LocationError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
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

// MARK: - Test double

@MainActor
private final class FakeLocationProvider: LocationProviding {
    var authorizationStatus: CLAuthorizationStatus
    weak var delegate: CLLocationManagerDelegate?
    private(set) var requestWhenInUseCallCount = 0
    private(set) var requestLocationCallCount = 0

    init(authorizationStatus: CLAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    nonisolated func requestWhenInUseAuthorization() {
        MainActor.assumeIsolated {
            requestWhenInUseCallCount += 1
        }
    }

    nonisolated func requestLocation() {
        MainActor.assumeIsolated {
            requestLocationCallCount += 1
        }
    }
}
