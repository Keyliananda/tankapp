import XCTest
@testable import Tankapp

final class TankerkoenigClientTests: XCTestCase {

    private let validKey = "11111111-2222-3333-4444-555555555555"
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        session = .mocked()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        session = nil
        super.tearDown()
    }

    // MARK: - URL building

    func test_searchStations_buildsCorrectURL() async throws {
        MockURLProtocol.responseData = fixture("list_ok")
        let client = TankerkoenigClient(apiKey: validKey, session: session)

        _ = try await client.searchStations(latitude: 52.034, longitude: 8.534, radiusKm: 5)

        let url = try XCTUnwrap(MockURLProtocol.lastRequestURL)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "creativecommons.tankerkoenig.de")
        XCTAssertEqual(url.path, "/json/list.php")

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(dict["lat"], "52.034")
        XCTAssertEqual(dict["lng"], "8.534")
        XCTAssertEqual(dict["rad"], "5.0")
        XCTAssertEqual(dict["sort"], "dist")
        XCTAssertEqual(dict["type"], "all")
        XCTAssertEqual(dict["apikey"], validKey)
    }

    func test_searchStations_clampsRadiusTo25() async throws {
        MockURLProtocol.responseData = fixture("list_ok")
        let client = TankerkoenigClient(apiKey: validKey, session: session)

        _ = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 999)

        let items = URLComponents(url: MockURLProtocol.lastRequestURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let rad = items.first(where: { $0.name == "rad" })?.value
        XCTAssertEqual(rad, "25.0")
    }

    func test_searchStations_clampsRadiusToMin1() async throws {
        MockURLProtocol.responseData = fixture("list_ok")
        let client = TankerkoenigClient(apiKey: validKey, session: session)

        _ = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 0.1)

        let items = URLComponents(url: MockURLProtocol.lastRequestURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let rad = items.first(where: { $0.name == "rad" })?.value
        XCTAssertEqual(rad, "1.0")
    }

    // MARK: - Decoding

    func test_searchStations_decodesAllStations() async throws {
        MockURLProtocol.responseData = fixture("list_ok")
        let client = TankerkoenigClient(apiKey: validKey, session: session)

        let stations = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 5)

        XCTAssertEqual(stations.count, 3)

        let aral = try XCTUnwrap(stations.first)
        XCTAssertEqual(aral.brand, "ARAL")
        XCTAssertEqual(aral.name, "ARAL Tankstelle")
        XCTAssertEqual(aral.distanceKm, 1.2)
        XCTAssertTrue(aral.isOpen)
        XCTAssertEqual(aral.price(for: .e5), 1.659)
        XCTAssertEqual(aral.price(for: .e10), 1.599)
        XCTAssertEqual(aral.price(for: .diesel), 1.529)
        XCTAssertEqual(aral.fullAddress, "Hauptstr. 12, 33602 Bielefeld")
    }

    func test_searchStations_treatsBoolPriceAsUnavailable() async throws {
        MockURLProtocol.responseData = fixture("list_ok")
        let client = TankerkoenigClient(apiKey: validKey, session: session)

        let stations = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 5)
        let shell = try XCTUnwrap(stations.first(where: { $0.brand == "SHELL" }))

        XCTAssertNil(shell.price(for: .e5), "false in JSON soll als nicht verfügbar gelten")
        XCTAssertEqual(shell.price(for: .e10), 1.589)
        XCTAssertEqual(shell.price(for: .diesel), 1.519)
    }

    func test_searchStations_treatsNullPriceAsUnavailable() async throws {
        MockURLProtocol.responseData = fixture("list_ok")
        let client = TankerkoenigClient(apiKey: validKey, session: session)

        let stations = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 5)
        let frei = try XCTUnwrap(stations.first(where: { $0.brand == "" }))

        XCTAssertNil(frei.price(for: .e10))
        XCTAssertEqual(frei.price(for: .e5), 1.629)
        XCTAssertFalse(frei.isOpen)
    }

    // MARK: - Errors

    func test_searchStations_throwsMissingAPIKey_whenKeyIsEmpty() async {
        let client = TankerkoenigClient(apiKey: "", session: session)
        await assertAsyncThrows(APIError.missingAPIKey) {
            _ = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 5)
        }
    }

    func test_searchStations_throwsMissingAPIKey_whenPlaceholder() async {
        let client = TankerkoenigClient(apiKey: "00000000-0000-0000-0000-000000000000", session: session)
        await assertAsyncThrows(APIError.missingAPIKey) {
            _ = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 5)
        }
    }

    func test_searchStations_throwsAPIError_whenOkFalse() async throws {
        MockURLProtocol.responseData = fixture("list_error")
        let client = TankerkoenigClient(apiKey: validKey, session: session)

        do {
            _ = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 5)
            XCTFail("Expected APIError.apiError")
        } catch APIError.apiError(let msg) {
            XCTAssertEqual(msg, "apikey nicht gefunden")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_searchStations_throwsHTTP_onNon2xx() async {
        MockURLProtocol.responseStatusCode = 503
        MockURLProtocol.responseData = Data()
        let client = TankerkoenigClient(apiKey: validKey, session: session)

        await assertAsyncThrows(APIError.http(503)) {
            _ = try await client.searchStations(latitude: 52, longitude: 8, radiusKm: 5)
        }
    }

    // MARK: - Helpers

    private func fixture(_ name: String) -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "json") else {
            XCTFail("Fixture \(name).json nicht gefunden")
            return Data()
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    private func assertAsyncThrows<E: Error & Equatable>(
        _ expected: E,
        _ block: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await block()
            XCTFail("Expected error \(expected)", file: file, line: line)
        } catch let error as E {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
