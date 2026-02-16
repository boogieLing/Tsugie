import Foundation

final class PlaceStampStore {
    private static let stampPrefixByFolder: [StampFolder: String] = [
        .sakuraInshou: "sakura-inshou__",
        .tsugieLogo: "tsugie-logo__",
        .momijiKinen: "momiji-kinen__"
    ]

    private enum StampFolder: String {
        case sakuraInshou
        case tsugieLogo
        case momijiKinen
    }

    private var lockedStamps: [UUID: String] = [:]
    private var transientStamps: [UUID: String] = [:]

    private let defaults: UserDefaults
    private let storageKey = "tsugie.placeStamp.v1"
    private let allStampResourceNames: [String]

    init(defaults: UserDefaults = .standard, allStampResourceNames: [String]? = nil) {
        self.defaults = defaults
        self.allStampResourceNames = allStampResourceNames ?? Self.discoverAllStampResourceNames()
        restore()
    }

    func refreshTransientStamp(for placeID: UUID, heType: HeType) {
        let previous = transientStamps[placeID]
        guard let sampled = sampleStamp(for: heType, excluding: previous) else {
            return
        }
        transientStamps[placeID] = sampled
    }

    func lockStampIfNeeded(for placeID: UUID, heType: HeType) {
        guard lockedStamps[placeID] == nil else {
            return
        }

        if let transient = transientStamps[placeID] {
            lockedStamps[placeID] = transient
            persist()
            return
        }

        guard let sampled = sampleStamp(for: heType) else {
            return
        }

        lockedStamps[placeID] = sampled
        persist()
    }

    func presentation(for placeID: UUID, heType: HeType, state: PlaceState) -> PlaceStampPresentation? {
        if state.isFavorite || state.isCheckedIn {
            lockStampIfNeeded(for: placeID, heType: heType)
        } else if transientStamps[placeID] == nil {
            refreshTransientStamp(for: placeID, heType: heType)
        }

        let resourceName = lockedStamps[placeID] ?? transientStamps[placeID]
        guard let resourceName else {
            return nil
        }

        return PlaceStampPresentation(
            resourceName: resourceName,
            isColorized: state.isCheckedIn
        )
    }

    private func sampleStamp(for heType: HeType, excluding excluded: String? = nil) -> String? {
        let folders = folders(for: heType)
        let shuffledFolders = folders.shuffled()

        for folder in shuffledFolders {
            guard let prefix = Self.stampPrefixByFolder[folder] else {
                continue
            }
            let candidates = allStampResourceNames.filter { $0.hasPrefix(prefix) }
            if let excluded,
               let picked = candidates.filter({ $0 != excluded }).randomElement() {
                return picked
            }
            if let picked = candidates.randomElement() {
                return picked
            }
        }

        return nil
    }

    private func folders(for heType: HeType) -> [StampFolder] {
        switch heType {
        case .nature:
            return [.sakuraInshou, .tsugieLogo]
        case .hanabi:
            return [.sakuraInshou, .tsugieLogo]
        case .other:
            return [.tsugieLogo, .momijiKinen]
        case .matsuri:
            return [.tsugieLogo, .sakuraInshou]
        }
    }

    private func persist() {
        let payload = Dictionary(uniqueKeysWithValues: lockedStamps.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    private func restore() {
        guard let data = defaults.data(forKey: storageKey),
              let payload = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }

        var restored: [UUID: String] = [:]
        for (key, value) in payload {
            guard let id = UUID(uuidString: key) else {
                continue
            }
            restored[id] = value
        }
        lockedStamps = restored
    }

    private static func discoverAllStampResourceNames() -> [String] {
        guard let resourceRoot = Bundle.main.resourceURL else {
            return []
        }

        let rootNames = (try? FileManager.default.contentsOfDirectory(atPath: resourceRoot.path)) ?? []
        let nestedNames: [String]
        if let nested = try? FileManager.default.contentsOfDirectory(atPath: resourceRoot.appendingPathComponent("stamps", isDirectory: true).path) {
            nestedNames = nested
        } else {
            nestedNames = []
        }

        return (rootNames + nestedNames)
            .filter { $0.lowercased().hasSuffix(".png") }
            .filter {
                $0.hasPrefix("sakura-inshou__") ||
                $0.hasPrefix("tsugie-logo__") ||
                $0.hasPrefix("momiji-kinen__")
            }
            .sorted()
    }
}
