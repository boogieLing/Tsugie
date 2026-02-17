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

    private struct StampSelection: Codable, Equatable {
        let resourceName: String
        let rotationDegrees: Double
    }

    private var lockedStamps: [UUID: StampSelection] = [:]
    private var transientStamps: [UUID: StampSelection] = [:]

    private let defaults: UserDefaults
    private let storageKey = "tsugie.placeStamp.v1"
    private let allStampResourceNames: [String]

    init(defaults: UserDefaults = .standard, allStampResourceNames: [String]? = nil) {
        self.defaults = defaults
        self.allStampResourceNames = allStampResourceNames ?? Self.discoverAllStampResourceNames()
        restore()
    }

    func refreshTransientStamp(for placeID: UUID, heType: HeType) {
        let previous = transientStamps[placeID]?.resourceName
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
            let selectedStamp = lockedStamps[placeID] ?? transientStamps[placeID]
            guard let selectedStamp else {
                return nil
            }
            return PlaceStampPresentation(
                resourceName: selectedStamp.resourceName,
                isColorized: state.isCheckedIn,
                rotationDegrees: selectedStamp.rotationDegrees
            )
        }

        if transientStamps[placeID] == nil {
            refreshTransientStamp(for: placeID, heType: heType)
        }

        guard let selectedStamp = transientStamps[placeID] else {
            return nil
        }

        return PlaceStampPresentation(
            resourceName: selectedStamp.resourceName,
            isColorized: state.isCheckedIn,
            rotationDegrees: selectedStamp.rotationDegrees
        )
    }

    private func sampleStamp(for heType: HeType, excluding excluded: String? = nil) -> StampSelection? {
        let folders = folders(for: heType)
        let shuffledFolders = folders.shuffled()

        for folder in shuffledFolders {
            guard let prefix = Self.stampPrefixByFolder[folder] else {
                continue
            }
            let candidates = allStampResourceNames.filter { $0.hasPrefix(prefix) }
            if let excluded,
               let picked = candidates.filter({ $0 != excluded }).randomElement() {
                return StampSelection(
                    resourceName: picked,
                    rotationDegrees: sampleCounterclockwiseRotationDegrees()
                )
            }
            if let picked = candidates.randomElement() {
                return StampSelection(
                    resourceName: picked,
                    rotationDegrees: sampleCounterclockwiseRotationDegrees()
                )
            }
        }

        return nil
    }

    private func sampleCounterclockwiseRotationDegrees() -> Double {
        -Double(Int.random(in: 15...34))
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
        guard let data = defaults.data(forKey: storageKey) else {
            return
        }

        if let payload = try? JSONDecoder().decode([String: StampSelection].self, from: data) {
            var restored: [UUID: StampSelection] = [:]
            for (key, value) in payload {
                guard let id = UUID(uuidString: key) else {
                    continue
                }
                restored[id] = value
            }
            lockedStamps = restored
            return
        }

        guard let legacyPayload = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }

        var restored: [UUID: String] = [:]
        for (key, value) in legacyPayload {
            guard let id = UUID(uuidString: key) else {
                continue
            }
            restored[id] = value
        }
        lockedStamps = Dictionary(
            uniqueKeysWithValues: restored.map {
                (
                    $0.key,
                    StampSelection(
                        resourceName: $0.value,
                        rotationDegrees: sampleCounterclockwiseRotationDegrees()
                    )
                )
            }
        )
        persist()
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
