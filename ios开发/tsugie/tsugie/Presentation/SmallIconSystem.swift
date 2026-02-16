import Foundation

enum TsugieSmallIcon {
    static let allAsset = "MainIconAll"
    static let sakuraAsset = "MainIconSakura"
    static let hanabiAsset = "MainIconHanabi"
    static let momijiAsset = "MainIconMomiji"
    static let omatsuriAsset = "MainIconOmatsuri"

    static func assetName(for heType: HeType) -> String {
        switch heType {
        case .hanabi:
            return hanabiAsset
        case .matsuri:
            return omatsuriAsset
        case .nature:
            return sakuraAsset
        case .other:
            return momijiAsset
        }
    }

    static func assetName(for categoryID: String) -> String {
        switch categoryID {
        case "hanabi":
            return hanabiAsset
        case "matsuri":
            return omatsuriAsset
        case "nature":
            return sakuraAsset
        case "other":
            return momijiAsset
        case "all":
            return allAsset
        default:
            return sakuraAsset
        }
    }

    static func assetName(for filter: MapPlaceCategoryFilter) -> String {
        switch filter {
        case .all:
            return allAsset
        case .hanabi:
            return hanabiAsset
        case .matsuri:
            return omatsuriAsset
        }
    }
}
