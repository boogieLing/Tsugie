import CoreLocation
import XCTest
@testable import tsugie

@MainActor
final class HomeMapViewModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "tsugie.tests.viewmodel.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMapCategoryFilterClearsInvisibleSelection() {
        let hanabi = makePlace(name: "hanabi", heType: .hanabi)
        let matsuri = makePlace(name: "matsuri", heType: .matsuri)
        let viewModel = HomeMapViewModel(places: [hanabi, matsuri], placeStateStore: PlaceStateStore(defaults: defaults))

        viewModel.openQuickCard(placeID: matsuri.id, keepMarkerActions: true)
        XCTAssertEqual(viewModel.selectedPlaceID, matsuri.id)
        XCTAssertEqual(viewModel.quickCardPlaceID, matsuri.id)

        viewModel.setMapCategoryFilter(.hanabi)

        XCTAssertNil(viewModel.selectedPlaceID)
        XCTAssertNil(viewModel.quickCardPlaceID)
        XCTAssertNil(viewModel.markerActionPlaceID)
    }

    func testFavoriteCountsReflectCheckedInStatus() {
        let first = makePlace(name: "A", heType: .hanabi)
        let second = makePlace(name: "B", heType: .matsuri)
        let viewModel = HomeMapViewModel(places: [first, second], placeStateStore: PlaceStateStore(defaults: defaults))

        viewModel.toggleFavorite(for: first.id)
        viewModel.toggleFavorite(for: second.id)
        viewModel.toggleCheckedIn(for: second.id)

        XCTAssertEqual(viewModel.favoriteFilterCount(.all), 2)
        XCTAssertEqual(viewModel.favoriteFilterCount(.planned), 1)
        XCTAssertEqual(viewModel.favoriteFilterCount(.checked), 1)
    }

    func testMapCategoryFilterCountUsesFullSet() {
        let first = makePlace(name: "A", heType: .hanabi)
        let second = makePlace(name: "B", heType: .matsuri)
        let third = makePlace(name: "C", heType: .matsuri)
        let viewModel = HomeMapViewModel(places: [first, second, third], placeStateStore: PlaceStateStore(defaults: defaults))

        XCTAssertEqual(viewModel.mapCategoryFilterCount(.all), 3)
        XCTAssertEqual(viewModel.mapCategoryFilterCount(.hanabi), 1)
        XCTAssertEqual(viewModel.mapCategoryFilterCount(.matsuri), 2)
    }

    func testNearbyCarouselUsesScoredRecommendationOrder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ongoing = makePlace(
            name: "ongoing",
            heType: .matsuri,
            startAt: now.addingTimeInterval(-30 * 60),
            endAt: now.addingTimeInterval(90 * 60),
            distanceMeters: 2_200,
            scaleScore: 86,
            heatScore: 88
        )
        let upcomingSoon = makePlace(
            name: "upcoming",
            heType: .matsuri,
            startAt: now.addingTimeInterval(60 * 60),
            endAt: now.addingTimeInterval(3 * 60 * 60),
            distanceMeters: 400,
            scaleScore: 60,
            heatScore: 60
        )
        let endedClose = makePlace(
            name: "ended",
            heType: .matsuri,
            startAt: now.addingTimeInterval(-4 * 60 * 60),
            endAt: now.addingTimeInterval(-60 * 60),
            distanceMeters: 120,
            scaleScore: 94,
            heatScore: 96
        )

        let viewModel = HomeMapViewModel(
            places: [endedClose, upcomingSoon, ongoing],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )
        let ordered = viewModel.nearbyCarouselItems(now: now, limit: 3).map(\.name)

        XCTAssertEqual(ordered, ["ongoing", "upcoming"])
    }

    func testNearbyCarouselPrioritizesHanabi() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let hanabi = makePlace(
            name: "hanabi-priority",
            heType: .hanabi,
            startAt: now.addingTimeInterval(90 * 60),
            endAt: now.addingTimeInterval(3 * 60 * 60),
            distanceMeters: 1_500,
            scaleScore: 75,
            heatScore: 70
        )
        let matsuri = makePlace(
            name: "matsuri-closer",
            heType: .matsuri,
            startAt: now.addingTimeInterval(60 * 60),
            endAt: now.addingTimeInterval(3 * 60 * 60),
            distanceMeters: 300,
            scaleScore: 90,
            heatScore: 90
        )

        let viewModel = HomeMapViewModel(
            places: [matsuri, hanabi],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )
        let ordered = viewModel.nearbyCarouselItems(now: now, limit: 2).map(\.name)

        XCTAssertEqual(ordered.first, "hanabi-priority")
    }

    private func makePlace(
        name: String,
        heType: HeType,
        startAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endAt: Date = Date(timeIntervalSince1970: 1_700_003_600),
        distanceMeters: Double = 500,
        scaleScore: Int = 80,
        heatScore: Int = 60
    ) -> HePlace {
        HePlace(
            id: UUID(),
            name: name,
            heType: heType,
            coordinate: CLLocationCoordinate2D(latitude: 35.7, longitude: 139.8),
            startAt: startAt,
            endAt: endAt,
            distanceMeters: distanceMeters,
            scaleScore: scaleScore,
            hint: "hint",
            openHours: nil,
            mapSpot: "map",
            detailDescription: "desc",
            imageTag: "tag",
            imageHint: "image",
            heatScore: heatScore,
            surpriseScore: 50
        )
    }
}
