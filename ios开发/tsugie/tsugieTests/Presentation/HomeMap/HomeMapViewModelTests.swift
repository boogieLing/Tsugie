import CoreLocation
import MapKit
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

    func testToggleCheckedInBlocksUpcomingAndShowsTopNotice() {
        let upcoming = makePlace(name: "upcoming", heType: .hanabi)
        let viewModel = HomeMapViewModel(
            places: [upcoming],
            placeStateStore: PlaceStateStore(defaults: defaults),
            checkInBlockedNoticeDurationNanoseconds: 300_000_000
        )

        viewModel.toggleCheckedIn(for: upcoming.id)

        XCTAssertFalse(viewModel.placeState(for: upcoming.id).isCheckedIn)
        XCTAssertEqual(viewModel.topNotice?.message, L10n.Home.checkInBlockedUpcoming)
    }

    func testToggleCheckedInAllowsOngoingEvent() {
        let now = Date()
        let ongoing = makePlace(
            name: "ongoing",
            heType: .matsuri,
            startAt: now.addingTimeInterval(-20 * 60),
            endAt: now.addingTimeInterval(40 * 60)
        )
        let viewModel = HomeMapViewModel(places: [ongoing], placeStateStore: PlaceStateStore(defaults: defaults))

        viewModel.toggleCheckedIn(for: ongoing.id)

        XCTAssertTrue(viewModel.placeState(for: ongoing.id).isCheckedIn)
        XCTAssertNil(viewModel.topNotice)
    }

    func testTopNoticeAutoDismissesAndIsClearedOnDisappear() async {
        let upcoming = makePlace(name: "upcoming", heType: .hanabi)
        let viewModel = HomeMapViewModel(
            places: [upcoming],
            placeStateStore: PlaceStateStore(defaults: defaults),
            checkInBlockedNoticeDurationNanoseconds: 40_000_000
        )

        viewModel.toggleCheckedIn(for: upcoming.id)
        XCTAssertNotNil(viewModel.topNotice)

        try? await Task.sleep(nanoseconds: 180_000_000)
        XCTAssertNil(viewModel.topNotice)

        viewModel.toggleCheckedIn(for: upcoming.id)
        XCTAssertNotNil(viewModel.topNotice)

        viewModel.onViewDisappear()
        XCTAssertNil(viewModel.topNotice)
    }

    func testResetToCurrentLocationAfterJumpUsesResolvedCoordinate() async {
        let jumpedPlace = makePlace(
            name: "jumped",
            heType: .hanabi,
            coordinate: CLLocationCoordinate2D(latitude: 34.6937, longitude: 135.5023)
        )
        let resolvedCoordinate = CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107)
        let viewModel = HomeMapViewModel(
            places: [jumpedPlace],
            placeStateStore: PlaceStateStore(defaults: defaults),
            locationProvider: FixedLocationProvider(coordinate: resolvedCoordinate)
        )

        viewModel.openQuickCard(placeID: jumpedPlace.id, keepMarkerActions: true)
        viewModel.resetToCurrentLocation()

        try? await Task.sleep(nanoseconds: 220_000_000)
        guard let region = viewModel.mapPosition.region else {
            return XCTFail("expected map position to be region")
        }

        XCTAssertEqual(region.center.latitude, resolvedCoordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(region.center.longitude, resolvedCoordinate.longitude, accuracy: 0.0001)
    }

    func testStaleInteractionUpdateCannotOverrideResetLocationTarget() async {
        let jumpedPlace = makePlace(
            name: "jumped",
            heType: .hanabi,
            coordinate: CLLocationCoordinate2D(latitude: 34.6937, longitude: 135.5023)
        )
        let resolvedCoordinate = CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107)
        let viewModel = HomeMapViewModel(
            places: [jumpedPlace],
            placeStateStore: PlaceStateStore(defaults: defaults),
            locationProvider: FixedLocationProvider(coordinate: resolvedCoordinate)
        )

        viewModel.openQuickCard(placeID: jumpedPlace.id, keepMarkerActions: true)
        viewModel.resetToCurrentLocation()

        try? await Task.sleep(nanoseconds: 200_000_000)
        viewModel.updateMapPositionFromInteraction(
            .region(
                MKCoordinateRegion(
                    center: jumpedPlace.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                )
            )
        )

        guard let region = viewModel.mapPosition.region else {
            return XCTFail("expected map position to be region")
        }
        XCTAssertEqual(region.center.latitude, resolvedCoordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(region.center.longitude, resolvedCoordinate.longitude, accuracy: 0.0001)
    }

    func testStaleInteractionAfterProgrammaticCameraCallbackCannotOverrideResetTarget() async {
        let jumpedPlace = makePlace(
            name: "jumped",
            heType: .hanabi,
            coordinate: CLLocationCoordinate2D(latitude: 34.6937, longitude: 135.5023)
        )
        let resolvedCoordinate = CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107)
        let viewModel = HomeMapViewModel(
            places: [jumpedPlace],
            placeStateStore: PlaceStateStore(defaults: defaults),
            locationProvider: FixedLocationProvider(coordinate: resolvedCoordinate)
        )

        viewModel.openQuickCard(placeID: jumpedPlace.id, keepMarkerActions: true)
        viewModel.resetToCurrentLocation()

        try? await Task.sleep(nanoseconds: 220_000_000)
        guard let resetRegion = viewModel.mapPosition.region else {
            return XCTFail("expected map position to be region")
        }

        // Simulate the programmatic camera onEnd callback that arrives right after reset.
        viewModel.handleMapCameraChange(resetRegion)
        // Simulate a stale old interaction update arriving after the callback above.
        viewModel.updateMapPositionFromInteraction(
            .region(
                MKCoordinateRegion(
                    center: jumpedPlace.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                )
            )
        )

        guard let region = viewModel.mapPosition.region else {
            return XCTFail("expected map position to be region")
        }
        XCTAssertEqual(region.center.latitude, resolvedCoordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(region.center.longitude, resolvedCoordinate.longitude, accuracy: 0.0001)
    }

    func testResetToCurrentLocationImmediatelyReturnsToAnchorEvenIfLocationResolutionIsSlow() async {
        let jumpedPlace = makePlace(
            name: "jumped",
            heType: .hanabi,
            coordinate: CLLocationCoordinate2D(latitude: 34.6937, longitude: 135.5023)
        )
        let delayedResolvedCoordinate = CLLocationCoordinate2D(latitude: 43.0642, longitude: 141.3469)
        let viewModel = HomeMapViewModel(
            places: [jumpedPlace],
            placeStateStore: PlaceStateStore(defaults: defaults),
            locationProvider: DelayedLocationProvider(
                coordinate: delayedResolvedCoordinate,
                delayNanoseconds: 1_200_000_000
            )
        )

        viewModel.openQuickCard(placeID: jumpedPlace.id, keepMarkerActions: true)
        viewModel.resetToCurrentLocation()

        guard let immediateRegion = viewModel.mapPosition.region else {
            return XCTFail("expected immediate map position to be region")
        }
        XCTAssertEqual(
            immediateRegion.center.latitude,
            DefaultAppLocationProvider.developmentFixedCoordinate.latitude,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            immediateRegion.center.longitude,
            DefaultAppLocationProvider.developmentFixedCoordinate.longitude,
            accuracy: 0.0001
        )

        try? await Task.sleep(nanoseconds: 1_400_000_000)
        guard let resolvedRegion = viewModel.mapPosition.region else {
            return XCTFail("expected resolved map position to be region")
        }
        XCTAssertEqual(resolvedRegion.center.latitude, delayedResolvedCoordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(resolvedRegion.center.longitude, delayedResolvedCoordinate.longitude, accuracy: 0.0001)
    }

    func testTapSelectedMarkerClosesQuickCardAndClearsSelection() {
        let place = makePlace(name: "hanabi", heType: .hanabi)
        let viewModel = HomeMapViewModel(places: [place], placeStateStore: PlaceStateStore(defaults: defaults))

        viewModel.openQuickCard(placeID: place.id, keepMarkerActions: true)
        XCTAssertEqual(viewModel.selectedPlaceID, place.id)
        XCTAssertEqual(viewModel.quickCardPlaceID, place.id)
        XCTAssertEqual(viewModel.markerActionPlaceID, place.id)

        viewModel.tapMarker(placeID: place.id)

        XCTAssertNil(viewModel.selectedPlaceID)
        XCTAssertNil(viewModel.quickCardPlaceID)
        XCTAssertNil(viewModel.markerActionPlaceID)
    }

    func testTapSelectedMarkerWithoutCardDismissesSelection() {
        let place = makePlace(name: "matsuri", heType: .matsuri)
        let viewModel = HomeMapViewModel(places: [place], placeStateStore: PlaceStateStore(defaults: defaults))

        viewModel.openQuickCard(placeID: place.id, keepMarkerActions: true, showPanel: false)
        XCTAssertEqual(viewModel.selectedPlaceID, place.id)
        XCTAssertNil(viewModel.quickCardPlaceID)
        XCTAssertEqual(viewModel.markerActionPlaceID, place.id)

        viewModel.tapMarker(placeID: place.id)

        XCTAssertNil(viewModel.selectedPlaceID)
        XCTAssertNil(viewModel.quickCardPlaceID)
        XCTAssertNil(viewModel.markerActionPlaceID)
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

    func testToggleSideDrawerDefaultsToFavoritesMenuWithoutOpeningFavoriteDrawer() {
        let place = makePlace(name: "A", heType: .hanabi)
        let viewModel = HomeMapViewModel(places: [place], placeStateStore: PlaceStateStore(defaults: defaults))

        viewModel.toggleSideDrawerPanel()

        XCTAssertTrue(viewModel.isSideDrawerOpen)
        XCTAssertEqual(viewModel.sideDrawerMenu, .favorites)
        XCTAssertFalse(viewModel.isFavoriteDrawerOpen)
    }

    func testCloseFavoriteDrawerKeepsFavoritesSelectedAndDrawerClosed() {
        let place = makePlace(name: "A", heType: .hanabi)
        let viewModel = HomeMapViewModel(places: [place], placeStateStore: PlaceStateStore(defaults: defaults))

        viewModel.openFavoriteDrawer()
        XCTAssertTrue(viewModel.isFavoriteDrawerOpen)
        XCTAssertEqual(viewModel.sideDrawerMenu, .favorites)

        viewModel.closeFavoriteDrawer()

        XCTAssertTrue(viewModel.isSideDrawerOpen)
        XCTAssertEqual(viewModel.sideDrawerMenu, .favorites)
        XCTAssertFalse(viewModel.isFavoriteDrawerOpen)
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

    func testNearbyCarouselFusesSurpriseScoreIntoOrdering() {
        let now = Date()
        let lowSurprise = makePlace(
            name: "low-surprise",
            heType: .matsuri,
            startAt: now.addingTimeInterval(5 * 60 * 60),
            endAt: now.addingTimeInterval(7 * 60 * 60),
            distanceMeters: 900,
            scaleScore: 70,
            heatScore: 66,
            surpriseScore: 22
        )
        let highSurprise = makePlace(
            name: "high-surprise",
            heType: .matsuri,
            startAt: now.addingTimeInterval(5 * 60 * 60),
            endAt: now.addingTimeInterval(7 * 60 * 60),
            distanceMeters: 900,
            scaleScore: 70,
            heatScore: 66,
            surpriseScore: 94
        )

        let viewModel = HomeMapViewModel(
            places: [lowSurprise, highSurprise],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )
        let ordered = viewModel.nearbyCarouselItems(now: now, limit: 2).map(\.name)

        XCTAssertEqual(ordered.first, "high-surprise")
    }

    func testNearbyCarouselPrioritizesNearbyOngoingWhenCompetingWithUpcomingHotSpot() {
        let now = Date()
        let ongoingNear = makePlace(
            name: "ongoing-near",
            heType: .matsuri,
            startAt: now.addingTimeInterval(-20 * 60),
            endAt: now.addingTimeInterval(80 * 60),
            distanceMeters: 250,
            scaleScore: 72,
            heatScore: 70,
            surpriseScore: 62
        )
        let upcomingHot = makePlace(
            name: "upcoming-hot",
            heType: .matsuri,
            startAt: now.addingTimeInterval(30 * 60),
            endAt: now.addingTimeInterval(3 * 60 * 60),
            distanceMeters: 80,
            scaleScore: 96,
            heatScore: 96,
            surpriseScore: 95
        )

        let viewModel = HomeMapViewModel(
            places: [upcomingHot, ongoingNear],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )
        let ordered = viewModel.nearbyCarouselItems(now: now, limit: 2).map(\.name)

        XCTAssertEqual(ordered.first, "ongoing-near")
    }

    func testNearbyCarouselPrefersKnownTimeOverUnknownEvenIfUnknownIsCloser() {
        let now = Date()
        let unknownClose = makePlace(
            name: "unknown-close",
            heType: .matsuri,
            startAt: nil,
            endAt: nil,
            distanceMeters: 60,
            scaleScore: 70,
            heatScore: 90
        )
        let upcomingKnown = makePlace(
            name: "known-upcoming",
            heType: .matsuri,
            startAt: now.addingTimeInterval(8 * 60 * 60),
            endAt: now.addingTimeInterval(10 * 60 * 60),
            distanceMeters: 4_200,
            scaleScore: 60,
            heatScore: 30
        )

        let viewModel = HomeMapViewModel(
            places: [unknownClose, upcomingKnown],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )

        let ordered = viewModel.nearbyPlaces(now: now, limit: 2).map(\.name)
        XCTAssertEqual(ordered, ["known-upcoming", "unknown-close"])
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

    func testNearbyCarouselBecomesEmptyInNoActivityViewport() async {
        let now = Date()
        let nearTokyoA = makePlace(
            name: "tokyo-a",
            heType: .matsuri,
            startAt: now.addingTimeInterval(2 * 60 * 60),
            endAt: now.addingTimeInterval(4 * 60 * 60),
            distanceMeters: 600,
            coordinate: CLLocationCoordinate2D(latitude: 35.7103, longitude: 139.8108)
        )
        let nearTokyoB = makePlace(
            name: "tokyo-b",
            heType: .hanabi,
            startAt: now.addingTimeInterval(3 * 60 * 60),
            endAt: now.addingTimeInterval(5 * 60 * 60),
            distanceMeters: 900,
            coordinate: CLLocationCoordinate2D(latitude: 35.7089, longitude: 139.8089)
        )
        let viewModel = HomeMapViewModel(
            places: [nearTokyoA, nearTokyoB],
            placeStateStore: PlaceStateStore(defaults: defaults)
        )

        viewModel.onViewAppear()
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(viewModel.nearbyCarouselItems(now: now, limit: 3).isEmpty)

        viewModel.handleMapCameraChange(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0.0, longitude: -140.0),
                span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
            )
        )
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(viewModel.nearbyCarouselItems(now: now, limit: 3).isEmpty)
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
        surpriseScore: Int = 50,
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
            surpriseScore: surpriseScore
        )
    }

    private struct FixedLocationProvider: AppLocationProviding {
        let coordinate: CLLocationCoordinate2D

        func resolveCurrentLocation(fallback: CLLocationCoordinate2D) async -> AppLocationResolution {
            AppLocationResolution(coordinate: coordinate, fallbackReason: nil)
        }
    }

    private struct DelayedLocationProvider: AppLocationProviding {
        let coordinate: CLLocationCoordinate2D
        let delayNanoseconds: UInt64

        func resolveCurrentLocation(fallback: CLLocationCoordinate2D) async -> AppLocationResolution {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            return AppLocationResolution(coordinate: coordinate, fallbackReason: nil)
        }
    }
}
