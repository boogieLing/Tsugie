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
    let geoSource: String
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

    init(
        id: UUID,
        name: String,
        heType: HeType,
        coordinate: CLLocationCoordinate2D,
        geoSource: String = "unknown",
        startAt: Date?,
        endAt: Date?,
        distanceMeters: Double,
        scaleScore: Int,
        hint: String,
        openHours: String?,
        mapSpot: String,
        detailDescription: String,
        imageTag: String,
        imageHint: String,
        heatScore: Int,
        surpriseScore: Int
    ) {
        self.id = id
        self.name = name
        self.heType = heType
        self.coordinate = coordinate
        self.geoSource = geoSource
        self.startAt = startAt
        self.endAt = endAt
        self.distanceMeters = distanceMeters
        self.scaleScore = scaleScore
        self.hint = hint
        self.openHours = openHours
        self.mapSpot = mapSpot
        self.detailDescription = detailDescription
        self.imageTag = imageTag
        self.imageHint = imageHint
        self.heatScore = heatScore
        self.surpriseScore = surpriseScore
    }

    var isApproximateCoordinate: Bool {
        geoSource == "pref_center_fallback" || geoSource == "missing"
    }
}
    
