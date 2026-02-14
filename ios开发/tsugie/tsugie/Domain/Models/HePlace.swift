import CoreLocation
import Foundation

enum HeType: String, CaseIterable, Codable {
    case hanabi
    case matsuri
    case nature
    case other
}

struct HePlace: Identifiable {
    let id: UUID
    let name: String
    let heType: HeType
    let coordinate: CLLocationCoordinate2D
    let startAt: Date?
    let endAt: Date?
    let distanceMeters: Double
    let scaleScore: Int
    let hint: String
    let openHours: String?
    let mapSpot: String
    let detailDescription: String
    let imageTag: String
    let imageHint: String
    let heatScore: Int
    let surpriseScore: Int
}
