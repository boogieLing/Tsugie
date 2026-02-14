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
                hint: "✨ (ง •̀_•́)ง いま出発が最適",
                openHours: "開放時間 19:20 - 20:35",
                mapSpot: "隅田川テラス側、南西エリア",
                detailDescription: "川沿いの視界が広く、写真映えしやすいエリア。混雑前に到着すると体験が安定します。",
                imageTag: "花火",
                imageHint: "川沿いの視界が広く、写真映えしやすいエリア",
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
                hint: "🏮 いま境内の熱気が高まっています",
                openHours: "開放時間 18:00 - 22:00",
                mapSpot: "雷門側の境内中央エリア",
                detailDescription: "祭りの導線が分散しているため、参道側から回遊すると混雑を避けやすいです。",
                imageTag: "祭り",
                imageHint: "提灯の明かりが濃く、夜の回遊が楽しい",
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
                hint: "🌙 余韻散歩に向いた静かな視点場",
                openHours: "開放時間 17:30 - 21:00",
                mapSpot: "押上駅東側の見晴らしポイント",
                detailDescription: "終演後の余韻を楽しむスポット。短時間滞在でも雰囲気を掴みやすい場所です。",
                imageTag: "夜景",
                imageHint: "高所から街明かりが一望できる穏やかな場所",
                heatScore: 66,
                surpriseScore: 70
            )
        ]
    }
}
