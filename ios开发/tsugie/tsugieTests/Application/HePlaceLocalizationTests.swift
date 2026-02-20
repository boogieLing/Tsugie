import CoreLocation
import XCTest
@testable import tsugie

final class HePlaceLocalizationTests: XCTestCase {
    func testLocalizedDetailDescriptionUsesChineseWhenLanguageIsChinese() {
        let place = makePlace(
            detailDescription: "日本語紹介",
            detailDescriptionZH: "中文介绍",
            detailDescriptionEN: "English intro"
        )

        XCTAssertEqual(place.localizedDetailDescription(for: "zh-Hans"), "中文介绍")
        XCTAssertEqual(place.localizedDetailDescription(for: "zh_CN"), "中文介绍")
    }

    func testLocalizedDetailDescriptionFallsBackByLanguagePriority() {
        let place = makePlace(
            detailDescription: "日本語紹介",
            detailDescriptionZH: "中文介绍",
            detailDescriptionEN: "English intro"
        )

        XCTAssertEqual(place.localizedDetailDescription(for: "en-US"), "English intro")
        XCTAssertEqual(place.localizedDetailDescription(for: "ja-JP"), "日本語紹介")
    }

    func testLocalizedOneLinerFallsBackToAvailableLanguage() {
        let place = makePlace(
            oneLiner: nil,
            oneLinerZH: "中文一句话",
            oneLinerEN: "English one-liner"
        )

        XCTAssertEqual(place.localizedOneLiner(for: "ja"), "中文一句话")
        XCTAssertEqual(place.localizedOneLiner(for: "zh-Hans"), "中文一句话")
        XCTAssertEqual(place.localizedOneLiner(for: "en"), "English one-liner")
    }

    private func makePlace(
        detailDescription: String = "日本語紹介",
        oneLiner: String? = "日本語一句话",
        detailDescriptionZH: String? = "中文介绍",
        oneLinerZH: String? = "中文一句话",
        detailDescriptionEN: String? = "English intro",
        oneLinerEN: String? = "English one-liner"
    ) -> HePlace {
        HePlace(
            id: UUID(),
            name: "test-place",
            heType: .matsuri,
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 139.0),
            startAt: nil,
            endAt: nil,
            distanceMeters: 120,
            scaleScore: 60,
            hint: "hint",
            openHours: "17:00-21:00",
            mapSpot: "Tokyo",
            detailDescription: detailDescription,
            oneLiner: oneLiner,
            detailDescriptionZH: detailDescriptionZH,
            oneLinerZH: oneLinerZH,
            detailDescriptionEN: detailDescriptionEN,
            oneLinerEN: oneLinerEN,
            sourceURLs: [],
            descriptionSourceURL: nil,
            imageSourceURL: nil,
            imageRef: nil,
            imageTag: "matsuri",
            imageHint: "hint",
            heatScore: 50,
            surpriseScore: 60
        )
    }
}
