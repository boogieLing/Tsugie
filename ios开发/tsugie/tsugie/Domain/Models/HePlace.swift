import CoreLocation
import Foundation

enum HeType: String, CaseIterable, Codable {
    case hanabi
    case matsuri
    case nature
    case other
}

struct HePlaceImageRef: Sendable {
    let payloadOffset: UInt64
    let payloadLength: Int
    let payloadSHA256: String?
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
    let oneLiner: String?
    let detailDescriptionZH: String?
    let oneLinerZH: String?
    let detailDescriptionEN: String?
    let oneLinerEN: String?
    let launchCount: String?
    let launchScale: String?
    let paidSeat: String?
    let accessText: String?
    let parkingText: String?
    let trafficControlText: String?
    let organizer: String?
    let festivalType: String?
    let admissionFee: String?
    let expectedVisitors: String?
    let sourceURLs: [String]
    let descriptionSourceURL: String?
    let imageSourceURL: String?
    let imageRef: HePlaceImageRef?
    let imageTag: String
    let imageHint: String
    let heatScore: Int
    let surpriseScore: Int

    nonisolated init(
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
        oneLiner: String? = nil,
        detailDescriptionZH: String? = nil,
        oneLinerZH: String? = nil,
        detailDescriptionEN: String? = nil,
        oneLinerEN: String? = nil,
        launchCount: String? = nil,
        launchScale: String? = nil,
        paidSeat: String? = nil,
        accessText: String? = nil,
        parkingText: String? = nil,
        trafficControlText: String? = nil,
        organizer: String? = nil,
        festivalType: String? = nil,
        admissionFee: String? = nil,
        expectedVisitors: String? = nil,
        sourceURLs: [String] = [],
        descriptionSourceURL: String? = nil,
        imageSourceURL: String? = nil,
        imageRef: HePlaceImageRef? = nil,
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
        self.oneLiner = oneLiner
        self.detailDescriptionZH = detailDescriptionZH
        self.oneLinerZH = oneLinerZH
        self.detailDescriptionEN = detailDescriptionEN
        self.oneLinerEN = oneLinerEN
        self.launchCount = launchCount
        self.launchScale = launchScale
        self.paidSeat = paidSeat
        self.accessText = accessText
        self.parkingText = parkingText
        self.trafficControlText = trafficControlText
        self.organizer = organizer
        self.festivalType = festivalType
        self.admissionFee = admissionFee
        self.expectedVisitors = expectedVisitors
        self.sourceURLs = sourceURLs
        self.descriptionSourceURL = descriptionSourceURL
        self.imageSourceURL = imageSourceURL
        self.imageRef = imageRef
        self.imageTag = imageTag
        self.imageHint = imageHint
        self.heatScore = heatScore
        self.surpriseScore = surpriseScore
    }

    nonisolated var isApproximateCoordinate: Bool {
        geoSource == "pref_center_fallback" || geoSource == "missing"
    }

    var hasImageAsset: Bool {
        guard let imageRef else { return false }
        return imageRef.payloadLength > 0
    }

    func localizedDetailDescription(for languageCode: String) -> String {
        switch Self.normalizedLanguageCode(languageCode) {
        case "zh-Hans":
            return Self.firstNonEmpty(detailDescriptionZH, detailDescriptionEN, detailDescription) ?? detailDescription
        case "en":
            return Self.firstNonEmpty(detailDescriptionEN, detailDescriptionZH, detailDescription) ?? detailDescription
        default:
            return Self.firstNonEmpty(detailDescription, detailDescriptionZH, detailDescriptionEN) ?? detailDescription
        }
    }

    func localizedOneLiner(for languageCode: String) -> String? {
        switch Self.normalizedLanguageCode(languageCode) {
        case "zh-Hans":
            return Self.firstNonEmpty(oneLinerZH, oneLinerEN, oneLiner)
        case "en":
            return Self.firstNonEmpty(oneLinerEN, oneLinerZH, oneLiner)
        default:
            return Self.firstNonEmpty(oneLiner, oneLinerZH, oneLinerEN)
        }
    }

    private static func normalizedLanguageCode(_ code: String) -> String {
        let lowered = code.lowercased()
        if lowered.hasPrefix("zh") {
            return "zh-Hans"
        }
        if lowered.hasPrefix("en") {
            return "en"
        }
        return "ja"
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }
}
    
