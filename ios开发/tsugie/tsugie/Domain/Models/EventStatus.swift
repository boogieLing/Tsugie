import Foundation

enum EventStatus: String, CaseIterable, Codable {
    case upcoming
    case ongoing
    case ended
    case unknown
}
