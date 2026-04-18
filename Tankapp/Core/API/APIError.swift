import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case network(String)
    case http(Int)
    case decoding(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Kein Tankerkönig-API-Key konfiguriert."
        case .invalidURL:
            return "Ungültige Anfrage-URL."
        case .network(let msg):
            return "Netzwerkfehler: \(msg)"
        case .http(let code):
            return "HTTP-Fehler \(code)."
        case .decoding(let msg):
            return "Antwort konnte nicht gelesen werden: \(msg)"
        case .apiError(let msg):
            return "Tankerkönig-API: \(msg)"
        }
    }
}
