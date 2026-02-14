import Foundation

final class PlaceStateStore {
    private var states: [UUID: PlaceState] = [:]

    private let defaults: UserDefaults
    private let storageKey = "tsugie.placeState.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restore()
    }

    func state(for placeID: UUID) -> PlaceState {
        states[placeID] ?? PlaceState()
    }

    func toggleFavorite(for placeID: UUID) {
        var value = state(for: placeID)
        value.isFavorite.toggle()
        states[placeID] = value
        persist()
    }

    func toggleCheckedIn(for placeID: UUID) {
        var value = state(for: placeID)
        value.isCheckedIn.toggle()
        if value.isCheckedIn {
            value.isFavorite = true
        }
        states[placeID] = value
        persist()
    }

    private func persist() {
        let payload = Dictionary(uniqueKeysWithValues: states.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func restore() {
        guard let data = defaults.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode([String: PlaceState].self, from: data) else {
            return
        }

        var restored: [UUID: PlaceState] = [:]
        for (key, value) in payload {
            guard let id = UUID(uuidString: key) else {
                continue
            }
            restored[id] = value
        }
        states = restored
    }
}
