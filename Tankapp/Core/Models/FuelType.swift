import Foundation

enum FuelType: String, CaseIterable, Identifiable, Hashable {
    case e5
    case e10
    case diesel

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .e5: return "Super E5"
        case .e10: return "Super E10"
        case .diesel: return "Diesel"
        }
    }

    var shortName: String {
        switch self {
        case .e5: return "E5"
        case .e10: return "E10"
        case .diesel: return "Diesel"
        }
    }
}
