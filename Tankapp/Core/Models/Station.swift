import CoreLocation
import Foundation

struct Station: Identifiable, Hashable {
    let id: String
    let name: String
    let brand: String
    let street: String
    let houseNumber: String?
    let postCode: Int?
    let place: String
    let latitude: Double
    let longitude: Double
    let distanceKm: Double
    let isOpen: Bool
    let prices: [FuelType: Double]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var fullAddress: String {
        let streetLine = [street, houseNumber].compactMap { $0 }.joined(separator: " ")
        let cityLine = [postCode.map(String.init), place].compactMap { $0 }.joined(separator: " ")
        return [streetLine, cityLine].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func price(for fuelType: FuelType) -> Double? {
        prices[fuelType]
    }
}
