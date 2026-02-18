import CoreLocation
import XCTest
@testable import tsugie

final class AppLocationProviderTests: XCTestCase {
    func testDevelopmentFixedModeAlwaysReturnsSkytreeCoordinate() async {
        let provider = DefaultAppLocationProvider(mode: .developmentFixed)
        let fallback = CLLocationCoordinate2D(latitude: 34.6937, longitude: 135.5023)

        let coordinate = await provider.currentCoordinate(fallback: fallback)

        XCTAssertEqual(
            coordinate.latitude,
            DefaultAppLocationProvider.developmentFixedCoordinate.latitude,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            coordinate.longitude,
            DefaultAppLocationProvider.developmentFixedCoordinate.longitude,
            accuracy: 0.000_001
        )
    }

    func testIsInJapanReturnsTrueForTokyoSkytree() {
        XCTAssertTrue(DefaultAppLocationProvider.isInJapan(.init(latitude: 35.7101, longitude: 139.8107)))
    }

    func testIsInJapanReturnsFalseForOutsideJapanCoordinate() {
        XCTAssertFalse(DefaultAppLocationProvider.isInJapan(.init(latitude: 37.5665, longitude: 126.9780)))
    }
}
