import Foundation

final class PlaceDecorationStore {
    private enum DecorationFolder: String {
        case hanabiKingyoKinen = "hanabi-kingyo-kinen"
        case hanabiBloomStamp = "hanabi-bloom-stamp"
        case hanabiKanzashiKinen = "hanabi-kanzashi-kinen"
        case kitsuneMen = "kitsune-men"
        case momijiLogo = "momiji-logo"
    }

    private static let fallbackAssetByType: [HeType: String] = [
        .hanabi: "MainIconHanabi",
        .matsuri: "MainIconOmatsuri",
        .nature: "MainIconMomiji",
        .other: "MainIconAll"
    ]

    private var assignedDecorations: [UUID: PlaceDecorationPresentation] = [:]
    private let allBundleResourceNames: [String]

    init(allBundleResourceNames: [String]? = nil) {
        self.allBundleResourceNames = allBundleResourceNames ?? Self.discoverAllBundleResourceNames()
    }

    func presentation(for placeID: UUID, heType: HeType) -> PlaceDecorationPresentation? {
        if let assigned = assignedDecorations[placeID] {
            retainOnly(placeID: placeID)
            return assigned
        }

        if let sampled = sampleResourceName(for: heType) {
            let assigned = PlaceDecorationPresentation(resourceName: normalizedResourceName(sampled), isAssetCatalog: false)
            assignedDecorations[placeID] = assigned
            retainOnly(placeID: placeID)
            return assigned
        }

        guard let fallbackAsset = Self.fallbackAssetByType[heType] else {
            return nil
        }
        let assigned = PlaceDecorationPresentation(resourceName: fallbackAsset, isAssetCatalog: true)
        assignedDecorations[placeID] = assigned
        retainOnly(placeID: placeID)
        return assigned
    }

    func retainOnly(placeID: UUID?) {
        guard let placeID else {
            assignedDecorations.removeAll(keepingCapacity: false)
            return
        }
        guard let selectedDecoration = assignedDecorations[placeID] else {
            assignedDecorations.removeAll(keepingCapacity: false)
            return
        }
        assignedDecorations = [placeID: selectedDecoration]
    }

    private func sampleResourceName(for heType: HeType) -> String? {
        let folders = folders(for: heType).shuffled()
        for folder in folders {
            let candidates = allBundleResourceNames.filter { resourceName in
                Self.resourceName(resourceName, belongsTo: folder)
            }
            if let picked = candidates.randomElement() {
                return normalizedResourceName(picked)
            }
        }
        return nil
    }

    private func normalizedResourceName(_ resourceName: String) -> String {
        URL(fileURLWithPath: resourceName).lastPathComponent
    }

    private func folders(for heType: HeType) -> [DecorationFolder] {
        switch heType {
        case .hanabi, .matsuri:
            return [.hanabiKingyoKinen, .hanabiBloomStamp, .hanabiKanzashiKinen, .kitsuneMen]
        case .nature, .other:
            return [.momijiLogo]
        }
    }

    private static func resourceName(_ resourceName: String, belongsTo folder: DecorationFolder) -> Bool {
        let normalizedPath = resourceName.lowercased()
        let folderName = folder.rawValue.lowercased()
        let fileName = URL(fileURLWithPath: normalizedPath).lastPathComponent

        if fileName.hasPrefix("\(folderName)__") {
            return true
        }
        if normalizedPath.hasPrefix("\(folderName)/") {
            return true
        }
        return normalizedPath.contains("/\(folderName)/")
    }

    private static func discoverAllBundleResourceNames() -> [String] {
        guard let resourceRoot = Bundle.main.resourceURL else {
            return []
        }
        let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "heic", "gif"]
        let rootPath = resourceRoot.path

        guard let enumerator = FileManager.default.enumerator(
            at: resourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var names: [String] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                continue
            }
            let path = fileURL.path
            guard path.hasPrefix(rootPath) else {
                continue
            }
            let relative = String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            names.append(relative)
        }

        return names.sorted()
    }
}
