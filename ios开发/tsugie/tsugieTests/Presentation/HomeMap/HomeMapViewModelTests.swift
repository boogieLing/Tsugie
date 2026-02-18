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
        let now = Date()
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
        let now = Date()
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

    func testNearbyCarouselPrefersSoonerStartWhenDistanceGapIsSmall() {
        let now = Date()
        let placeA = makePlace(
            name: "later-75d",
            heType: .matsuri,
            startAt: now.addingTimeInterval(75 * 24 * 60 * 60),
            endAt: now.addingTimeInterval((75 * 24 + 2) * 60 * 60),
            distanceMeters: 1_200,
            scaleScore: 80,
            heatScore: 70
        )
        let placeB = makePlace(
            name: "sooner-27d",
            heType: .matsuri,
            startAt: now.addingTimeInterval(27 * 24 * 60 * 60),
            endAt: now.addingTimeInterval((27 * 24 + 2) * 60 * 60),
            distanceMeters: 1_400,
            scaleScore: 80,
            heatScore: 70
        )

        let viewModel = HomeMapViewModel(
            places: [placeA, placeB],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )
        let ordered = viewModel.nearbyCarouselItems(now: now, limit: 2).map(\.name)

        XCTAssertEqual(ordered.first, "sooner-27d")
    }

    func testNearbyCarouselCanIncludePlacesOutsideCurrentViewportEnvelope() async {
        let now = Date()
        let inViewport = makePlace(
            name: "in-viewport",
            heType: .matsuri,
            startAt: now.addingTimeInterval(12 * 60 * 60),
            endAt: now.addingTimeInterval(14 * 60 * 60),
            distanceMeters: 900,
            scaleScore: 70,
            heatScore: 65,
            coordinate: CLLocationCoordinate2D(latitude: 35.7103, longitude: 139.8108)
        )
        let outOfViewportButNearby = makePlace(
            name: "out-viewport-nearby",
            heType: .matsuri,
            startAt: now.addingTimeInterval(2 * 60 * 60),
            endAt: now.addingTimeInterval(4 * 60 * 60),
            distanceMeters: 1_300,
            scaleScore: 70,
            heatScore: 65,
            coordinate: CLLocationCoordinate2D(latitude: 35.7560, longitude: 139.8108)
        )

        let viewModel = HomeMapViewModel(
            places: [inViewport, outOfViewportButNearby],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )
        viewModel.onViewAppear()
        try? await Task.sleep(nanoseconds: 500_000_000)

        let visibleIDs = Set(viewModel.mapPlaces().map(\.id))
        XCTAssertFalse(visibleIDs.contains(outOfViewportButNearby.id))

        let nearbyNames = viewModel.nearbyCarouselItems(now: now, limit: 2).map(\.name)
        XCTAssertEqual(nearbyNames.first, "out-viewport-nearby")
    }

    func testFastestFavoritePlacesPrefersOngoingThenSoonestUpcoming() {
        let now = Date()
        let ongoing = makePlace(
            name: "ongoing",
            heType: .hanabi,
            startAt: now.addingTimeInterval(-30 * 60),
            endAt: now.addingTimeInterval(90 * 60),
            distanceMeters: 2_000
        )
        let upcomingSoon = makePlace(
            name: "upcoming-soon",
            heType: .matsuri,
            startAt: now.addingTimeInterval(20 * 60),
            endAt: now.addingTimeInterval(120 * 60),
            distanceMeters: 800
        )
        let upcomingLater = makePlace(
            name: "upcoming-later",
            heType: .matsuri,
            startAt: now.addingTimeInterval(80 * 60),
            endAt: now.addingTimeInterval(180 * 60),
            distanceMeters: 400
        )
        let ended = makePlace(
            name: "ended",
            heType: .matsuri,
            startAt: now.addingTimeInterval(-4 * 60 * 60),
            endAt: now.addingTimeInterval(-1 * 60 * 60),
            distanceMeters: 300
        )
        let unknown = makePlace(
            name: "unknown",
            heType: .matsuri,
            startAt: nil,
            endAt: nil,
            distanceMeters: 200
        )

        let viewModel = HomeMapViewModel(
            places: [upcomingLater, unknown, ongoing, ended, upcomingSoon],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )
        [ongoing, upcomingSoon, upcomingLater, ended, unknown].forEach { place in
            viewModel.toggleFavorite(for: place.id)
        }

        let fastest = viewModel.fastestFavoritePlaces(now: now, limit: 2).map(\.name)
        XCTAssertEqual(fastest, ["ongoing", "upcoming-soon"])
    }

    private func makePlace(
        name: String,
        heType: HeType,
        startAt: Date? = Date().addingTimeInterval(10 * 60),
        endAt: Date? = Date().addingTimeInterval(110 * 60),
        distanceMeters: Double = 500,
        scaleScore: Int = 80,
        heatScore: Int = 60,
        coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 35.7, longitude: 139.8)
    ) -> HePlace {
        HePlace(
            id: UUID(),
            name: name,
            heType: heType,
            coordinate: coordinate,
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
