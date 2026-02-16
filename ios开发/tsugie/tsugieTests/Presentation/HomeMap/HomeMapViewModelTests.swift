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

    private func makePlace(name: String, heType: HeType) -> HePlace {
        HePlace(
            id: UUID(),
            name: name,
            heType: heType,
            coordinate: CLLocationCoordinate2D(latitude: 35.7, longitude: 139.8),
            startAt: Date(timeIntervalSince1970: 1_700_000_000),
            endAt: Date(timeIntervalSince1970: 1_700_003_600),
            distanceMeters: 500,
            scaleScore: 80,
            hint: "hint",
            openHours: nil,
            mapSpot: "map",
            detailDescription: "desc",
            imageTag: "tag",
            imageHint: "image",
            heatScore: 60,
            surpriseScore: 50
        )
    }
}
