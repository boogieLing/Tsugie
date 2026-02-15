import CoreLocation
import Foundation

enum MockHePlaceRepository {
    static func load() -> [HePlace] {
        let now = Date()
        let oneHour: TimeInterval = 60 * 60

        return [
            HePlace(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "隅田川花火会場",
                heType: .hanabi,
                coordinate: CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107),
                startAt: now.addingTimeInterval(oneHour * 2),
                endAt: now.addingTimeInterval(oneHour * 5),
                distanceMeters: 680,
                scaleScore: 95,
                hint: L10n.MockPlace.sumidaHint,
                openHours: L10n.Common.openHours("19:20 - 20:35"),
                mapSpot: L10n.MockPlace.sumidaMapSpot,
                detailDescription: L10n.MockPlace.sumidaDesc,
                imageTag: L10n.MockPlace.sumidaImageTag,
                imageHint: L10n.MockPlace.sumidaImageHint,
                heatScore: 82,
                surpriseScore: 76
            ),
            HePlace(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "浅草寺境内イベント",
                heType: .matsuri,
                coordinate: CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967),
                startAt: now.addingTimeInterval(-oneHour),
                endAt: now.addingTimeInterval(oneHour * 3),
                distanceMeters: 1250,
                scaleScore: 80,
                hint: L10n.MockPlace.asakusaHint,
                openHours: L10n.Common.openHours("18:00 - 22:00"),
                mapSpot: L10n.MockPlace.asakusaMapSpot,
                detailDescription: L10n.MockPlace.asakusaDesc,
                imageTag: L10n.MockPlace.asakusaImageTag,
                imageHint: L10n.MockPlace.asakusaImageHint,
                heatScore: 78,
                surpriseScore: 72
            ),
            HePlace(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                name: "押上ナイトビュー",
                heType: .nature,
                coordinate: CLLocationCoordinate2D(latitude: 35.7100, longitude: 139.8136),
                startAt: now.addingTimeInterval(-oneHour * 5),
                endAt: now.addingTimeInterval(-oneHour * 2),
                distanceMeters: 540,
                scaleScore: 70,
                hint: L10n.MockPlace.oshiageHint,
                openHours: L10n.Common.openHours("17:30 - 21:00"),
                mapSpot: L10n.MockPlace.oshiageMapSpot,
                detailDescription: L10n.MockPlace.oshiageDesc,
                imageTag: L10n.MockPlace.oshiageImageTag,
                imageHint: L10n.MockPlace.oshiageImageHint,
                heatScore: 66,
                surpriseScore: 70
            )
        ]
    }
}
