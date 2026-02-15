import Foundation
import XCTest
@testable import tsugie

final class PlaceStateStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "tsugie.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultStateIsNotFavoriteAndNotCheckedIn() {
        let store = PlaceStateStore(defaults: defaults)
        let state = store.state(for: UUID())

        XCTAssertFalse(state.isFavorite)
        XCTAssertFalse(state.isCheckedIn)
    }

    func testToggleFavoritePersistsAcrossStoreInstances() {
        let placeID = UUID()

        let store = PlaceStateStore(defaults: defaults)
        store.toggleFavorite(for: placeID)
        XCTAssertTrue(store.state(for: placeID).isFavorite)

        let restored = PlaceStateStore(defaults: defaults)
        XCTAssertTrue(restored.state(for: placeID).isFavorite)
    }

    func testToggleCheckedInAlsoSetsFavorite() {
        let placeID = UUID()
        let store = PlaceStateStore(defaults: defaults)

        store.toggleCheckedIn(for: placeID)
        let state = store.state(for: placeID)

        XCTAssertTrue(state.isCheckedIn)
        XCTAssertTrue(state.isFavorite)
    }

    func testUncheckDoesNotClearFavoriteFlag() {
        let placeID = UUID()
        let store = PlaceStateStore(defaults: defaults)

        store.toggleCheckedIn(for: placeID)
        store.toggleCheckedIn(for: placeID)
        let state = store.state(for: placeID)

        XCTAssertFalse(state.isCheckedIn)
        XCTAssertTrue(state.isFavorite)
    }
}
