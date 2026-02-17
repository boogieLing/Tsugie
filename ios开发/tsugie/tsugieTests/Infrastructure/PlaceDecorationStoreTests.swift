import Foundation
import XCTest
@testable import tsugie

final class PlaceDecorationStoreTests: XCTestCase {
    func testTypeFolderMappingUsesConfiguredDecorationFolders() {
        let resources = [
            "static/icon/hanabi-kingyo-kinen/1.png",
            "static/icon/hanabi-bloom-stamp/2.png",
            "static/icon/hanabi-kanzashi-kinen/3.png",
            "static/icon/kitsune-men/4.png",
            "static/icon/momiji-logo/5.png"
        ]
        let store = PlaceDecorationStore(allBundleResourceNames: resources)

        let hanabi = store.presentation(for: UUID(), heType: .hanabi)
        let matsuri = store.presentation(for: UUID(), heType: .matsuri)
        let nature = store.presentation(for: UUID(), heType: .nature)

        XCTAssertNotNil(hanabi)
        XCTAssertNotNil(matsuri)
        XCTAssertNotNil(nature)
        XCTAssertEqual(hanabi?.isAssetCatalog, false)
        XCTAssertEqual(matsuri?.isAssetCatalog, false)
        XCTAssertEqual(nature?.isAssetCatalog, false)

        let hanabiOrMatsuriFolders = [
            "hanabi-kingyo-kinen",
            "hanabi-bloom-stamp",
            "hanabi-kanzashi-kinen",
            "kitsune-men"
        ]
        XCTAssertTrue(hanabiOrMatsuriFolders.contains { hanabi?.resourceName.contains($0) == true })
        XCTAssertTrue(hanabiOrMatsuriFolders.contains { matsuri?.resourceName.contains($0) == true })
        XCTAssertEqual(nature?.resourceName.contains("momiji-logo"), true)
    }

    func testSelectionIsStableForSamePlaceID() {
        let resources = [
            "static/icon/hanabi-kingyo-kinen/1.png",
            "static/icon/kitsune-men/4.png"
        ]
        let store = PlaceDecorationStore(allBundleResourceNames: resources)
        let placeID = UUID()

        let first = store.presentation(for: placeID, heType: .hanabi)
        let second = store.presentation(for: placeID, heType: .hanabi)

        XCTAssertEqual(first, second)
    }

    func testFallbackToAssetIconWhenNoDecorationFilesExist() {
        let store = PlaceDecorationStore(allBundleResourceNames: [])
        let presentation = store.presentation(for: UUID(), heType: .matsuri)

        XCTAssertNotNil(presentation)
        XCTAssertEqual(presentation?.isAssetCatalog, true)
        XCTAssertEqual(presentation?.resourceName, "MainIconOmatsuri")
    }
}
