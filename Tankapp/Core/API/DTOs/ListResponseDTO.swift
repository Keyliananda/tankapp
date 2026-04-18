import Foundation

struct ListResponseDTO: Decodable {
    let ok: Bool
    let license: String?
    let data: String?
    let status: String?
    let message: String?
    let stations: [StationDTO]?
}

struct StationDTO: Decodable {
    let id: String
    let name: String
    let brand: String
    let street: String
    let houseNumber: String?
    let postCode: Int?
    let place: String
    let lat: Double
    let lng: Double
    let dist: Double
    let isOpen: Bool
    let diesel: PriceValue?
    let e5: PriceValue?
    let e10: PriceValue?
}

enum PriceValue: Decodable, Equatable {
    case value(Double)
    case unavailable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .unavailable
            return
        }
        if (try? container.decode(Bool.self)) != nil {
            self = .unavailable
            return
        }
        if let number = try? container.decode(Double.self), number > 0 {
            self = .value(number)
            return
        }
        self = .unavailable
    }

    var doubleValue: Double? {
        if case .value(let v) = self { return v }
        return nil
    }
}

extension StationDTO {
    func toDomain() -> Station {
        var prices: [FuelType: Double] = [:]
        if let v = diesel?.doubleValue { prices[.diesel] = v }
        if let v = e5?.doubleValue { prices[.e5] = v }
        if let v = e10?.doubleValue { prices[.e10] = v }

        return Station(
            id: id,
            name: name,
            brand: brand,
            street: street,
            houseNumber: houseNumber,
            postCode: postCode,
            place: place,
            latitude: lat,
            longitude: lng,
            distanceKm: dist,
            isOpen: isOpen,
            prices: prices
        )
    }
}
