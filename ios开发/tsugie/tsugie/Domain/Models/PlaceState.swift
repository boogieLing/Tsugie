import Foundation

struct PlaceState: Codable, Equatable {
    var isFavorite: Bool
    var isCheckedIn: Bool

    init(isFavorite: Bool = false, isCheckedIn: Bool = false) {
        self.isFavorite = isFavorite
        self.isCheckedIn = isCheckedIn
    }
}
