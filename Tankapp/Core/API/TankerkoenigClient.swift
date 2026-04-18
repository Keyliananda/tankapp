import Foundation

protocol TankerkoenigAPI {
    func searchStations(
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) async throws -> [Station]
}

final class TankerkoenigClient: TankerkoenigAPI {
    static let baseURL = URL(string: "https://creativecommons.tankerkoenig.de/json/")!

    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        self.decoder = JSONDecoder()
    }

    /// Sucht Tankstellen im Umkreis. Liefert IMMER alle Spritsorten (sort=dist, type=all),
    /// damit das ViewModel client-seitig filtern und sortieren kann ohne neue Anfrage.
    func searchStations(
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) async throws -> [Station] {
        guard !apiKey.isEmpty, apiKey != "00000000-0000-0000-0000-000000000000" else {
            throw APIError.missingAPIKey
        }

        let clampedRadius = min(max(radiusKm, 1), 25)

        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("list.php"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lng", value: String(longitude)),
            URLQueryItem(name: "rad", value: String(clampedRadius)),
            URLQueryItem(name: "sort", value: "dist"),
            URLQueryItem(name: "type", value: "all"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]

        guard let url = components?.url else { throw APIError.invalidURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }

        let dto: ListResponseDTO
        do {
            dto = try decoder.decode(ListResponseDTO.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }

        guard dto.ok else {
            throw APIError.apiError(dto.message ?? "Unbekannter Fehler")
        }

        return (dto.stations ?? []).map { $0.toDomain() }
    }
}

extension TankerkoenigClient {
    /// Liest den API-Key aus der Info.plist (gespeist aus Secrets.xcconfig).
    static func fromBundle(_ bundle: Bundle = .main) -> TankerkoenigClient {
        let key = bundle.object(forInfoDictionaryKey: "TankerkoenigAPIKey") as? String ?? ""
        return TankerkoenigClient(apiKey: key)
    }
}
