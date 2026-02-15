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
}
