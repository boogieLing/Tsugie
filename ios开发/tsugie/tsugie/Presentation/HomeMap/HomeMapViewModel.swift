import CoreLocation
import Combine
import MapKit
import os
import SwiftUI
import UIKit
import Darwin
import UserNotifications

enum SideDrawerMenu: String, CaseIterable {
    case none
    case favorites
    case notifications
    case contact
}

private extension UNUserNotificationCenter {
    func notificationSettingsAsync() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    func pendingNotificationIDs() async -> Set<String> {
        await withCheckedContinuation { continuation in
            getPendingNotificationRequests { requests in
                continuation.resume(returning: Set(requests.map(\.identifier)))
            }
        }
    }

    func deliveredNotificationIDs() async -> Set<String> {
        await withCheckedContinuation { continuation in
            getDeliveredNotifications { notifications in
                continuation.resume(returning: Set(notifications.map(\.request.identifier)))
            }
        }
    }
}

enum FavoriteDrawerFilter: String, CaseIterable {
    case all
    case planned
    case checked
}

struct MapPlaceCategoryFilter: RawRepresentable, Hashable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let all = Self(rawValue: "all")
    static let hanabi = Self(rawValue: "hanabi")
    static let matsuri = Self(rawValue: "matsuri")
    static let nature = Self(rawValue: "nature")
    static let other = Self(rawValue: "other")
    static let sakura = Self(rawValue: "sakura")
    static let momiji = Self(rawValue: "momiji")
}

private enum HomeMapSpatialCompute {
    struct ClusterFilterResult {
        let places: [HePlace]
        let dropped: Int
    }

    nonisolated static func filteredPlacesInRegion(_ source: [HePlace], region: MKCoordinateRegion) -> [HePlace] {
        let halfLat = region.span.latitudeDelta / 2
        let halfLng = region.span.longitudeDelta / 2
        return source.filter { place in
            abs(place.coordinate.latitude - region.center.latitude) <= halfLat &&
                abs(place.coordinate.longitude - region.center.longitude) <= halfLng
        }
    }

    nonisolated static func nearestPlacesByDistance(
        _ source: [HePlace],
        limit: Int,
        reference: CLLocationCoordinate2D
    ) -> [HePlace] {
        guard !source.isEmpty else {
            return []
        }
        let sorted = source.sorted { lhs, rhs in
            let lhsDistance = distanceMeters(from: reference, to: lhs.coordinate)
            let rhsDistance = distanceMeters(from: reference, to: rhs.coordinate)
            if lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }
            if lhs.scaleScore != rhs.scaleScore {
                return lhs.scaleScore > rhs.scaleScore
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return Array(sorted.prefix(max(1, limit)))
    }

    nonisolated static func ensureActivePlacesIncluded(
        in candidates: [HePlace],
        sourcePool: [HePlace],
        activeIDs: Set<UUID>,
        limit: Int,
        reference: CLLocationCoordinate2D
    ) -> [HePlace] {
        guard !sourcePool.isEmpty, limit > 0 else {
            return Array(candidates.prefix(max(0, limit)))
        }

        var result = Array(candidates.prefix(limit))
        guard !activeIDs.isEmpty else {
            return result
        }

        for activeID in activeIDs {
            guard result.contains(where: { $0.id == activeID }) == false else {
                continue
            }
            guard let activePlace = sourcePool.first(where: { $0.id == activeID }) else {
                continue
            }

            if result.count < limit {
                result.insert(activePlace, at: 0)
                continue
            }

            if let replaceIndex = result.lastIndex(where: { !activeIDs.contains($0.id) }) {
                result[replaceIndex] = activePlace
            } else if !result.isEmpty {
                result[result.count - 1] = activePlace
            }
        }

        return nearestPlacesByDistance(result, limit: limit, reference: reference)
    }

    nonisolated static func filterSuspectCoordinateClusters(
        _ source: [HePlace],
        threshold: Int,
        activeIDs: Set<UUID>
    ) -> ClusterFilterResult {
        guard source.count >= threshold else {
            return ClusterFilterResult(places: source, dropped: 0)
        }
        let grouped = Dictionary(grouping: source, by: coordinateKey(for:))
        let preservedRepresentativeByKey: [String: UUID] = grouped.compactMapValues { group in
            guard group.count >= threshold,
                  group.allSatisfy({ isLowConfidenceGeoSource($0.geoSource) }) else {
                return nil
            }
            return group.max { lhs, rhs in
                if lhs.scaleScore != rhs.scaleScore {
                    return lhs.scaleScore < rhs.scaleScore
                }
                if lhs.heatScore != rhs.heatScore {
                    return lhs.heatScore < rhs.heatScore
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            }?.id
        }

        var filtered: [HePlace] = []
        filtered.reserveCapacity(source.count)
        var dropped = 0

        for place in source {
            let key = coordinateKey(for: place)
            guard let group = grouped[key] else {
                filtered.append(place)
                continue
            }
            if group.count >= threshold &&
                !activeIDs.contains(place.id) &&
                group.allSatisfy({ isLowConfidenceGeoSource($0.geoSource) }) &&
                preservedRepresentativeByKey[key] != place.id {
                dropped += 1
                continue
            }
            filtered.append(place)
        }
        return ClusterFilterResult(places: filtered, dropped: dropped)
    }

    nonisolated private static func coordinateKey(for place: HePlace) -> String {
        "\(Int((place.coordinate.latitude * 1_000_000).rounded())):\(Int((place.coordinate.longitude * 1_000_000).rounded()))"
    }

    nonisolated private static func isLowConfidenceGeoSource(_ source: String) -> Bool {
        source == "missing" ||
            source == "pref_center_fallback" ||
            source.hasPrefix("network_geocode")
    }

    nonisolated private static func distanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lon1 = lhs.longitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let lon2 = rhs.longitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(1 - a, 0)))
        return earthRadiusMeters * c
    }
}

@MainActor
final class HomeMapViewModel: ObservableObject {
    private struct MarkerEntriesCacheKey: Equatable {
        let placesRevision: UInt64
        let statusTimeBucket: Int64
        let filter: MapPlaceCategoryFilter
        let selectedPlaceID: UUID?
        let markerActionPlaceID: UUID?
        let forcedExpandedPlaceID: UUID?
        let temporaryExpiredMarkerPlaceID: UUID?
        let isDetailVisible: Bool
        let visibleMenuState: PlaceState?
        let overlapCenterLatE3: Int
        let overlapSpanLatE4: Int
        let overlapSpanLngE4: Int
    }

    private struct MarkerClusterSummary {
        let anchor: HePlace
        let memberIDs: [UUID]

        var count: Int {
            memberIDs.count
        }
    }

    private struct ViewportQuerySignature: Equatable {
        let centerLatE3: Int
        let centerLngE3: Int
        let spanLatE3: Int
        let spanLngE3: Int
        let filter: MapPlaceCategoryFilter

        init(region: MKCoordinateRegion, filter: MapPlaceCategoryFilter) {
            centerLatE3 = Int((region.center.latitude * 1_000).rounded())
            centerLngE3 = Int((region.center.longitude * 1_000).rounded())
            spanLatE3 = Int((region.span.latitudeDelta * 1_000).rounded())
            spanLngE3 = Int((region.span.longitudeDelta * 1_000).rounded())
            self.filter = filter
        }
    }

    private struct NearbyPreheatSignature: Equatable {
        let centerLatE2: Int
        let centerLngE2: Int
        let radiusKmE1: Int

        init(center: CLLocationCoordinate2D, radiusKm: Double) {
            centerLatE2 = Int((center.latitude * 100).rounded())
            centerLngE2 = Int((center.longitude * 100).rounded())
            radiusKmE1 = Int((radiusKm * 10).rounded())
        }
    }

    private struct LocalNotificationCandidate {
        let identifier: String
        let triggerDate: Date
        let body: String
    }

    private struct ViewportRankingPayload {
        let rendered: [HePlace]
        let recommendation: [HePlace]
        let inRegionCount: Int
        let recommendationInRegionCount: Int
        let renderedDroppedCount: Int
        let recommendationDroppedCount: Int
    }

    private struct SideDrawerSnapshotCacheKey: Equatable {
        let sourceRevision: UInt64
        let usesRenderedSource: Bool
        let placeStateRevision: UInt64
    }

    private struct CalendarDetailSnapshotCacheKey: Equatable {
        let sourceRevision: UInt64
        let usesRenderedSource: Bool
        let daySerial: Int
    }

    private struct NearbyRankedEntry {
        let place: HePlace
        let snapshot: EventStatusSnapshot
        let score: Double
        let stage: Int
        let stageDelta: TimeInterval
    }

    private struct NearbyRankingCacheKey: Equatable {
        let recommendationRevision: UInt64
        let nowBucket: Int64
        let filter: MapPlaceCategoryFilter
    }

    private struct SideDrawerSnapshot {
        let favoritesAll: [HePlace]
        let favoritesPlanned: [HePlace]
        let favoritesChecked: [HePlace]
        let favoriteCounts: [FavoriteDrawerFilter: Int]
        let mapCategoryCounts: [MapPlaceCategoryFilter: Int]
        let mapCategoryFilters: [MapPlaceCategoryFilter]
    }

    struct LocationFallbackNotice: Identifiable {
        let reason: AppLocationFallbackReason

        var id: String {
            reason.rawValue
        }
    }

    struct TopNotice: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    private var mapCameraPosition: MapCameraPosition
    @Published private(set) var mapViewInstanceID = UUID()
    @Published private(set) var places: [HePlace]
    @Published private(set) var renderedPlaces: [HePlace]
    private var nearbyRecommendationPlaces: [HePlace]
    private var _selectedPlaceID: UUID?
    private var _markerActionPlaceID: UUID?
    private var _quickCardPlaceID: UUID?
    private var _expiredCardPlaceID: UUID?
    private var _temporaryExpiredMarkerPlaceID: UUID?
    private var _detailPlaceID: UUID?
    private var _forcedExpandedPlaceID: UUID?
    @Published private(set) var isCalendarPresented = false
    @Published private(set) var isSideDrawerOpen = false
    @Published private(set) var isFavoriteDrawerOpen = false
    @Published private(set) var locationFallbackNotice: LocationFallbackNotice?
    @Published private(set) var topNotice: TopNotice?
    @Published private(set) var sideDrawerMenu: SideDrawerMenu = .none
    @Published private(set) var favoriteFilter: FavoriteDrawerFilter = .all
    @Published private(set) var mapCategoryFilter: MapPlaceCategoryFilter = .all
    @Published var isThemePaletteOpen = false
    @Published var selectedThemeScheme = "sunset" {
        didSet { persistVisualAndNotificationSettingsIfReady() }
    }
    @Published var themeAlphaRatio: Double = 1 {
        didSet { persistVisualAndNotificationSettingsIfReady() }
    }
    @Published var themeSaturationRatio: Double = 1 {
        didSet { persistVisualAndNotificationSettingsIfReady() }
    }
    @Published var themeGlowRatio: Double = 1 {
        didSet { persistVisualAndNotificationSettingsIfReady() }
    }
    @Published var selectedLanguageCode: String = L10n.languageCode
    @Published var worldMode = false
    @Published var startNotificationEnabled = false {
        didSet { persistVisualAndNotificationSettingsIfReady() }
    }
    @Published var nearbyNotificationEnabled = false {
        didSet { persistVisualAndNotificationSettingsIfReady() }
    }

    private let logger = Logger(subsystem: "com.ushouldknowr0.tsugie", category: "HomeMapViewModel")
    private let placeStateStore: PlaceStateStore
    private let placeStampStore: PlaceStampStore
    private let placeDecorationStore: PlaceDecorationStore
    private let locationProvider: AppLocationProviding
    private let initialCenter = DefaultAppLocationProvider.developmentFixedCoordinate
    private let settingsStore = UserDefaults.standard
    private let themeSchemeDefaultsKey = "tsugie.settings.theme.scheme"
    private let themeAlphaDefaultsKey = "tsugie.settings.theme.alphaRatio"
    private let themeSaturationDefaultsKey = "tsugie.settings.theme.saturationRatio"
    private let themeGlowDefaultsKey = "tsugie.settings.theme.glowRatio"
    private let startNotificationDefaultsKey = "tsugie.settings.notifications.startEnabled"
    private let nearbyNotificationDefaultsKey = "tsugie.settings.notifications.nearbyEnabled"
    private let defaultMapSpan = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    private let focusedMapSpan = MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
    private let focusedCenterLatitudeOffset: CLLocationDegrees = 0.0023
    private let mapRebuildDistanceKm: Double = 250
    private let cameraHardRecycleDistanceKm: Double = 180
    private let cameraHardRecycleCooldown: TimeInterval = 10
    private let cameraHardRecycleEveryMoves: Int = 14
    private let periodicHardRecycleInterval: TimeInterval = 180
    private let periodicHardRecycleIntervalNanoseconds: UInt64 = 180_000_000_000
    private let memoryWatchdogIntervalNanoseconds: UInt64 = 8_000_000_000
    private let memoryHardRecycleThresholdMB: Double = 380
    private let memoryEmergencyThresholdMB: Double = 460
    private let memoryEmergencyRenderedLimit: Int = 120
    private let interactionRetentionDaysAfterEnded: Int = 31
    private let suspectCoordinateClusterThreshold = 6
    private let idleTrimCooldown: TimeInterval = 1.8
    private let idleViewportTrimDelayNanoseconds: UInt64 = 1_200_000_000
    private let minMoveForIdleRecycleKm: Double = 1.2
    private let minZoomRatioForIdleRecycle: Double = 1.22
    private let minCameraMoveForViewportReloadKm: Double = 0.20
    private let minCameraZoomRatioForViewportReload: Double = 1.08
    private let cameraMotionQuietWindow: TimeInterval = 0.45
    private let cameraEndDebounceNanoseconds: UInt64 = 320_000_000
    private let periodicHardRecycleMotionQuietWindow: TimeInterval = 3.0
    private let programmaticCameraSuppressionWindow: TimeInterval = 0.28
    private let programmaticCameraCenterToleranceKm: Double = 0.9
    private let programmaticCameraSpanTolerance: CLLocationDegrees = 0.0035
    private let calendarDismissMapStabilizationWindow: TimeInterval = 0.9
    private let calendarDismissTransientZoomRatioThreshold: Double = 3.2
    private let calendarDismissTransientCenterToleranceKm: Double = 0.7
    private let minimumViewportRadiusKm: Double
    private let nearbyLimit: Int
    private let mapBufferScale: Double = 2.25
    private let nearbyRecommendationBufferScale: Double = 3.9
    private let idleTrimScale: Double = 1.25
    private let deferredLoadAllDelayNanoseconds: UInt64 = 650_000_000
    private let maxRenderedPlaces = 120
    private let maxNearbyRecommendationPlaces = 220
    private let markerCollisionPointThreshold: Double = 30
    private let minMarkerCollisionMeters: Double = 10
    private let markerStatusCacheTimeBucketSeconds: TimeInterval = 60
    private var shouldBootstrapFromBundled: Bool
    private var isLoadingAllPlaces = false
    private var didLoadAllPlaces = false
    private var resolvedCenter: CLLocationCoordinate2D
    private var autoOpenTask: DispatchWorkItem?
    private var bootstrapTask: Task<Void, Never>?
    private var deferredLoadAllTask: Task<Void, Never>?
    private var loadAllTask: Task<Void, Never>?
    private var deferredCameraEndTask: Task<Void, Never>?
    private var viewportReloadTask: Task<Void, Never>?
    private var idleRecycleTask: Task<Void, Never>?
    private var periodicHardRecycleTask: Task<Void, Never>?
    private var memoryWatchdogTask: Task<Void, Never>?
    private var nearbyLoadTask: Task<[HePlace], Never>?
    private var nearbyPreheatTask: Task<Void, Never>?
    private var activeNearbyQueryToken: UUID?
    private var lastNearbyPreheatSignature: NearbyPreheatSignature?
    private var lastViewportQuerySignature: ViewportQuerySignature?
    private var lastLoadedExpandedRegion: MKCoordinateRegion?
    private var mapZoomRestoreTask: Task<Void, Never>?
    private var quickCardPresentationTask: Task<Void, Never>?
    private var lastKnownMapRegion: MKCoordinateRegion?
    private var lastMapRecycleCenter: CLLocationCoordinate2D?
    private var lastMapRecycleSpan: MKCoordinateSpan?
    private var lastHardRecycleCenter: CLLocationCoordinate2D?
    private var lastHardRecycleAt: Date = .distantPast
    private var lastIdleTrimAt: Date = .distantPast
    private var hasSignificantMoveSinceLastRecycle = false
    private var cameraChangeRevision: UInt64 = 0
    private var cameraMoveCountSinceHardRecycle: Int = 0
    private var placesRevision: UInt64 = 1
    private var allPlacesRevision: UInt64 = 1
    private var placeStateRevision: UInt64 = 0
    private var markerEntriesCacheKey: MarkerEntriesCacheKey?
    private var markerEntriesCache: [MapMarkerEntry] = []
    private var markerEntriesIndexByID: [UUID: Int] = [:]
    private var nearbyRecommendationRevision: UInt64 = 1
    private var nearbyRankingCacheKey: NearbyRankingCacheKey?
    private var nearbyRankingCache: [NearbyRankedEntry] = []
    private var sideDrawerSnapshotCacheKey: SideDrawerSnapshotCacheKey?
    private var sideDrawerSnapshotCache: SideDrawerSnapshot?
    private var calendarDetailSnapshotCacheKey: CalendarDetailSnapshotCacheKey?
    private var calendarDetailSnapshotCache: [HePlace] = []
    private var hasAutoOpened = false
    private var hasStartedLaunchPrewarm = false
    private var shownLocationFallbackReasons: Set<AppLocationFallbackReason> = []
    private var ignoreMapTapUntil: Date?
    private var memoryWarningObserver: NSObjectProtocol?
    private var hasAppliedInitialRecommendationFocus = false
    private var initialRecommendationFocusRevision: UInt64?
    private var pendingProgrammaticCameraTargetRegion: MKCoordinateRegion?
    private var pendingProgrammaticCameraSource: String?
    private var pendingProgrammaticCameraExpiresAt: Date = .distantPast
    private var suppressCalendarDismissRecenteringUntil: Date = .distantPast
    private var pendingSettledCameraRegion: MKCoordinateRegion?
    private var suppressMapInteractionUpdatesUntil: Date = .distantPast
    private var lastCameraMotionAt: Date = .distantPast
    private var lastCameraMotionHeartbeatAt: Date = .distantPast
    private var didLoadPersistedVisualSettings = false
    private let quickCardPresentationAnimation = Animation.spring(response: 0.24, dampingFraction: 0.92)
    private let quickCardDismissAnimation = Animation.spring(response: 0.40, dampingFraction: 0.92)
    private let sideDrawerAnimation = Animation.spring(response: 0.40, dampingFraction: 0.88)
    private let favoriteDrawerOpenAnimation = Animation.spring(response: 0.46, dampingFraction: 0.90)
    private let favoriteDrawerCloseAnimation = Animation.spring(response: 0.62, dampingFraction: 0.94)
    private let nearbyRankingTimeBucketSeconds: TimeInterval = 20
    private let startReminderNotificationPrefix = "tsugie.notify.start."
    private let nearbyReminderNotificationPrefix = "tsugie.notify.nearby."
    private let startReminderLeadTime: TimeInterval = 97 * 60
    private let nearbyReminderLookahead: TimeInterval = 24 * 60 * 60
    private let minimumNotificationLeadTime: TimeInterval = 8
    private let maxStartReminderCount = 36
    private let maxNearbyReminderCount = 16
    private var startReminderSyncTask: Task<Void, Never>?
    private var nearbyReminderSyncTask: Task<Void, Never>?
    private var topNoticeDismissTask: Task<Void, Never>?
    private let checkInBlockedNoticeDurationNanoseconds: UInt64

    init(
        places: [HePlace]? = nil,
        placeStateStore: PlaceStateStore? = nil,
        placeStampStore: PlaceStampStore? = nil,
        placeDecorationStore: PlaceDecorationStore? = nil,
        locationProvider: AppLocationProviding? = nil,
        minimumViewportRadiusKm: Double = 1.2,
        nearbyLimit: Int = 240,
        checkInBlockedNoticeDurationNanoseconds: UInt64 = 2_200_000_000
    ) {
        let sourcePlaces = (places ?? [])
            .filter { $0.heType != .nature }
        self.places = sourcePlaces
        self.renderedPlaces = sourcePlaces
        self.nearbyRecommendationPlaces = sourcePlaces
        self.placeStateStore = placeStateStore ?? PlaceStateStore()
        self.placeStampStore = placeStampStore ?? PlaceStampStore()
        self.placeDecorationStore = placeDecorationStore ?? PlaceDecorationStore()
        self.locationProvider = locationProvider ?? DefaultAppLocationProvider()
        self.minimumViewportRadiusKm = max(0.5, minimumViewportRadiusKm)
        self.nearbyLimit = max(1, nearbyLimit)
        self.checkInBlockedNoticeDurationNanoseconds = max(100_000_000, checkInBlockedNoticeDurationNanoseconds)
        self.shouldBootstrapFromBundled = places == nil
        self.resolvedCenter = initialCenter
        self.placesRevision = 1

        let region = MKCoordinateRegion(
            center: initialCenter,
            span: defaultMapSpan
        )
        self.mapCameraPosition = .region(region)
        self.lastKnownMapRegion = region
        self.lastMapRecycleCenter = region.center
        self.lastMapRecycleSpan = region.span
        self.lastHardRecycleCenter = region.center
        loadPersistedVisualAndNotificationSettings()
        self.renderedPlaces = interactivePlaces(from: self.renderedPlaces, now: Date())
        self.nearbyRecommendationPlaces = interactivePlaces(from: self.nearbyRecommendationPlaces, now: Date())
    }

    var mapPosition: MapCameraPosition {
        mapCameraPosition
    }

    var currentLocationCoordinate: CLLocationCoordinate2D {
        resolvedCenter
    }

    var locationFallbackAlertTitle: String {
        L10n.Home.locationFallbackTitle
    }

    func locationFallbackAlertMessage(for notice: LocationFallbackNotice) -> String {
        switch notice.reason {
        case .outsideJapan:
            return L10n.Home.locationFallbackOutsideJapanMessage
        case .permissionDenied:
            return L10n.Home.locationFallbackPermissionDeniedMessage
        }
    }

    var now: Date {
        Date()
    }

    var calendarDetailPlaces: [HePlace] {
        calendarDetailSnapshot()
    }

    var quickCardPlace: HePlace? {
        guard let quickCardPlaceID = _quickCardPlaceID else {
            return nil
        }
        return place(for: quickCardPlaceID)
    }

    var expiredCardPlace: HePlace? {
        guard let expiredCardPlaceID = _expiredCardPlaceID else {
            return nil
        }
        return place(for: expiredCardPlaceID)
    }

    var detailPlace: HePlace? {
        guard let detailPlaceID = _detailPlaceID else {
            return nil
        }
        return place(for: detailPlaceID)
    }

    var selectedPlaceID: UUID? {
        _selectedPlaceID
    }

    var markerActionPlaceID: UUID? {
        _markerActionPlaceID
    }

    var quickCardPlaceID: UUID? {
        _quickCardPlaceID
    }

    var expiredCardPlaceID: UUID? {
        _expiredCardPlaceID
    }

    var detailPlaceID: UUID? {
        _detailPlaceID
    }

    var isDetailVisible: Bool {
        _detailPlaceID != nil
    }

    var activePillGradient: LinearGradient {
        TsugieVisuals.pillGradient(
            scheme: selectedThemeScheme,
            alphaRatio: themeAlphaRatio,
            saturationRatio: themeSaturationRatio
        )
    }

    var activeDrawerBackground: LinearGradient {
        TsugieVisuals.drawerBackground(
            scheme: selectedThemeScheme,
            alphaRatio: themeAlphaRatio,
            saturationRatio: themeSaturationRatio
        )
    }

    var activeMapGlowColor: Color {
        let glow = min(max(themeGlowRatio, 0.6), 1.8)
        return TsugieVisuals.mapGlowColor(
            scheme: selectedThemeScheme,
            alphaRatio: themeAlphaRatio * glow,
            saturationRatio: themeSaturationRatio * (0.92 + glow * 0.08)
        )
    }

    var selectedLanguageLocale: Locale {
        Locale(identifier: selectedLanguageCode)
    }

    var currentLanguageShortLabel: String {
        switch selectedLanguageCode {
        case "zh-Hans":
            return "中"
        case "en":
            return "EN"
        default:
            return "日"
        }
    }

    var currentLanguageDisplayName: String {
        switch selectedLanguageCode {
        case "zh-Hans":
            return L10n.SideDrawer.languageNameZhHans
        case "en":
            return L10n.SideDrawer.languageNameEn
        default:
            return L10n.SideDrawer.languageNameJa
        }
    }

    private func loadPersistedVisualAndNotificationSettings() {
        if let scheme = settingsStore.string(forKey: themeSchemeDefaultsKey), !scheme.isEmpty {
            selectedThemeScheme = scheme
        }

        if let storedAlpha = settingsStore.object(forKey: themeAlphaDefaultsKey) as? Double {
            themeAlphaRatio = min(max(storedAlpha, 0.4), 1.5)
        }
        if let storedSaturation = settingsStore.object(forKey: themeSaturationDefaultsKey) as? Double {
            themeSaturationRatio = min(max(storedSaturation, 0.4), 1.7)
        }
        if let storedGlow = settingsStore.object(forKey: themeGlowDefaultsKey) as? Double {
            themeGlowRatio = min(max(storedGlow, 0.6), 1.8)
        }

        if settingsStore.object(forKey: startNotificationDefaultsKey) != nil {
            startNotificationEnabled = settingsStore.bool(forKey: startNotificationDefaultsKey)
        }
        if settingsStore.object(forKey: nearbyNotificationDefaultsKey) != nil {
            nearbyNotificationEnabled = settingsStore.bool(forKey: nearbyNotificationDefaultsKey)
        }

        didLoadPersistedVisualSettings = true
    }

    private func persistVisualAndNotificationSettingsIfReady() {
        guard didLoadPersistedVisualSettings else {
            return
        }
        settingsStore.set(selectedThemeScheme, forKey: themeSchemeDefaultsKey)
        settingsStore.set(themeAlphaRatio, forKey: themeAlphaDefaultsKey)
        settingsStore.set(themeSaturationRatio, forKey: themeSaturationDefaultsKey)
        settingsStore.set(themeGlowRatio, forKey: themeGlowDefaultsKey)
        settingsStore.set(startNotificationEnabled, forKey: startNotificationDefaultsKey)
        settingsStore.set(nearbyNotificationEnabled, forKey: nearbyNotificationDefaultsKey)
    }

    func onViewAppear() {
        registerMemoryWarningObserverIfNeeded()
        startPeriodicHardRecycleTask()
        startMemoryWatchdogTask()
        if initialRecommendationFocusRevision == nil {
            initialRecommendationFocusRevision = cameraChangeRevision
        }
        debugLog("onViewAppear allPlaces=\(self.places.count) renderedPlaces=\(self.renderedPlaces.count) mapFilter=\(self.mapCategoryFilter.rawValue)")
        beginLaunchPrewarmIfNeeded()
        scheduleAutoOpenIfNeeded()
        if startNotificationEnabled {
            scheduleStartReminderSync()
        }
        if nearbyNotificationEnabled {
            scheduleNearbyReminderSync()
        }
    }

    func onViewDisappear() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        deferredLoadAllTask?.cancel()
        deferredLoadAllTask = nil
        deferredCameraEndTask?.cancel()
        deferredCameraEndTask = nil
        pendingSettledCameraRegion = nil
        viewportReloadTask?.cancel()
        viewportReloadTask = nil
        idleRecycleTask?.cancel()
        idleRecycleTask = nil
        periodicHardRecycleTask?.cancel()
        periodicHardRecycleTask = nil
        memoryWatchdogTask?.cancel()
        memoryWatchdogTask = nil
        nearbyLoadTask?.cancel()
        nearbyLoadTask = nil
        nearbyPreheatTask?.cancel()
        nearbyPreheatTask = nil
        activeNearbyQueryToken = nil
        lastNearbyPreheatSignature = nil
        nearbyRecommendationPlaces = []
        startReminderSyncTask?.cancel()
        startReminderSyncTask = nil
        nearbyReminderSyncTask?.cancel()
        nearbyReminderSyncTask = nil
        dismissTopNotice()
    }

    func dismissLocationFallbackNotice() {
        locationFallbackNotice = nil
    }

    func dismissTopNotice() {
        topNoticeDismissTask?.cancel()
        topNoticeDismissTask = nil
        topNotice = nil
    }

    func setCalendarPresented(_ presented: Bool) {
        guard isCalendarPresented != presented else {
            return
        }
        isCalendarPresented = presented
        if presented {
            cancelPendingQuickCardPresentation()
            cancelPendingMapZoomRestore()
            closeSideDrawerPanel()
            closeMarkerActionBubble()
        } else {
            suppressMapInteractionUpdatesUntil = Date().addingTimeInterval(calendarDismissMapStabilizationWindow)
            let shouldSkipDismissRecentering = Date() <= suppressCalendarDismissRecenteringUntil
            if shouldSkipDismissRecentering {
                debugLog("skipCalendarDismissRecentering reason=externalNavigation")
            } else if let pinnedRegion = normalizedRegion(lastKnownMapRegion ?? mapCameraPosition.region) {
                setProgrammaticMapPosition(.region(pinnedRegion))
            }
        }
    }

    func beginLaunchPrewarmIfNeeded() {
        guard !hasStartedLaunchPrewarm else {
            return
        }
        hasStartedLaunchPrewarm = true
        bootstrapNearbyPlacesIfNeeded()
        _ = mapMarkerEntries()
        prewarmSideDrawerSnapshotForLaunch()
        prewarmCalendarCacheForLaunch()
    }

    func prepareForCalendarPlaceNavigation() {
        suppressCalendarDismissRecenteringUntil = Date().addingTimeInterval(1.5)
    }

    func tapMarker(placeID: UUID) {
        guard _detailPlaceID == nil else { return }
        markAnnotationTapCooldown()
        cancelPendingQuickCardPresentation()
        cancelPendingMapZoomRestore()
        cancelPendingMapFocus()

        guard let targetPlace = placeForInteraction(placeID) else {
            return
        }

        if _selectedPlaceID == placeID {
            if _markerActionPlaceID == placeID {
                // Keep selection sticky while marker action menu is visible.
                // This avoids accidental deselection when a near-miss lands on the marker body.
                markAnnotationTapCooldown(0.4)
                return
            }
            let currentPlaceState = placeStateStore.state(for: placeID)
            if !currentPlaceState.isFavorite && !currentPlaceState.isCheckedIn {
                placeStampStore.refreshTransientStamp(for: placeID, heType: targetPlace.heType)
                objectWillChange.send()
            }
            withAnimation(quickCardDismissAnimation) {
                if _quickCardPlaceID != nil || _expiredCardPlaceID != nil {
                    closeActiveBottomCard(restoreMapZoom: true)
                } else {
                    dismissMarkerSelection(restoreMapZoom: true)
                }
            }
            return
        }

        let focusPlace: HePlace? = shouldFocusQuickCard(place: targetPlace) ? targetPlace : nil
        withAnimation(quickCardPresentationAnimation) {
            openQuickCard(
                placeID: placeID,
                keepMarkerActions: true,
                showPanel: true,
                focusPlace: focusPlace
            )
        }
    }

    func closeMarkerActionBubble() {
        dismissMarkerSelection(restoreMapZoom: false)
    }

    func markAnnotationTapCooldown(_ duration: TimeInterval = 0.3) {
        ignoreMapTapUntil = Date().addingTimeInterval(duration)
    }

    func handleMapBackgroundTap() {
        if let until = ignoreMapTapUntil, Date() < until {
            return
        }
        if _quickCardPlaceID != nil || _expiredCardPlaceID != nil {
            withAnimation(quickCardDismissAnimation) {
                closeActiveBottomCard(restoreMapZoom: true)
            }
            return
        }
        dismissMarkerSelection(restoreMapZoom: true)
    }

    private func dismissMarkerSelection(restoreMapZoom: Bool) {
        guard _markerActionPlaceID != nil || _selectedPlaceID != nil else {
            return
        }
        cancelPendingQuickCardPresentation()
        cancelPendingMapFocus()
        let focusedPlaceID = _selectedPlaceID
        mutateInteractionState {
            _markerActionPlaceID = nil
            _selectedPlaceID = nil
            _forcedExpandedPlaceID = nil
        }
        if restoreMapZoom, _detailPlaceID == nil {
            scheduleMapZoomRestoreAfterSelectionDismiss(focusedPlaceID: focusedPlaceID)
        }
    }

    func openQuickCard(
        placeID: UUID,
        keepMarkerActions: Bool = false,
        showPanel: Bool = true,
        focusPlace: HePlace? = nil
    ) {
        guard let targetPlace = placeForInteraction(placeID) else {
            return
        }
        resetMapCategoryFilterIfNeeded(for: targetPlace)
        ensureRenderedContains(targetPlace)
        let currentPlaceState = placeStateStore.state(for: placeID)
        if showPanel && !currentPlaceState.isFavorite && !currentPlaceState.isCheckedIn {
            placeStampStore.refreshTransientStamp(for: placeID, heType: targetPlace.heType)
        }
        cancelPendingMapZoomRestore()
        let overlapRegion = normalizedRegion(lastKnownMapRegion ?? mapCameraPosition.region) ?? MKCoordinateRegion(
            center: resolvedCenter,
            span: defaultMapSpan
        )
        let shouldForceExpandedMarker = isOverlapClusterPlace(targetPlace, region: overlapRegion)
        let resolvedFocusPlace: HePlace?
        if let focusPlace, isPlaceInteractionEnabled(focusPlace) {
            resolvedFocusPlace = focusPlace
        } else {
            resolvedFocusPlace = targetPlace
        }
        let focusedRegion = resolvedFocusPlace.map { nonExpandingFocusedRegion(for: $0) }
        mutateInteractionState {
            _selectedPlaceID = placeID
            _markerActionPlaceID = keepMarkerActions ? placeID : nil
            _detailPlaceID = nil
            _quickCardPlaceID = showPanel ? placeID : nil
            _expiredCardPlaceID = nil
            _temporaryExpiredMarkerPlaceID = nil
            _forcedExpandedPlaceID = shouldForceExpandedMarker ? placeID : nil
            if let focusedRegion,
               let normalizedFocusedRegion = normalizedRegion(focusedRegion) {
                mapCameraPosition = .region(normalizedFocusedRegion)
                lastKnownMapRegion = normalizedFocusedRegion
                registerProgrammaticCameraChangeTarget(
                    normalizedFocusedRegion,
                    source: "openQuickCardFocus"
                )
            }
        }
    }

    func closeQuickCard(restoreMapZoom: Bool = true) {
        cancelPendingQuickCardPresentation()
        let focusedPlaceID = _selectedPlaceID
        let shouldDismissMarkerSelection = _detailPlaceID == nil

        if shouldDismissMarkerSelection {
            cancelPendingMapFocus()
        }
        mutateInteractionState {
            _quickCardPlaceID = nil
            _forcedExpandedPlaceID = nil
            if shouldDismissMarkerSelection {
                _markerActionPlaceID = nil
                _selectedPlaceID = nil
            }
        }

        if shouldDismissMarkerSelection, restoreMapZoom {
            scheduleMapZoomRestoreAfterQuickDismiss(focusedPlaceID: focusedPlaceID)
        }
    }

    func closeExpiredCard(restoreMapZoom: Bool = true) {
        cancelPendingQuickCardPresentation()
        let focusedPlaceID = _selectedPlaceID
        let shouldDismissMarkerSelection = _detailPlaceID == nil

        if shouldDismissMarkerSelection {
            cancelPendingMapFocus()
        }
        mutateInteractionState {
            _expiredCardPlaceID = nil
            _temporaryExpiredMarkerPlaceID = nil
            _forcedExpandedPlaceID = nil
            if shouldDismissMarkerSelection {
                _markerActionPlaceID = nil
                _selectedPlaceID = nil
            }
        }

        if shouldDismissMarkerSelection, restoreMapZoom {
            scheduleMapZoomRestoreAfterQuickDismiss(focusedPlaceID: focusedPlaceID)
        }
    }

    private func closeActiveBottomCard(restoreMapZoom: Bool) {
        if _expiredCardPlaceID != nil {
            closeExpiredCard(restoreMapZoom: restoreMapZoom)
            return
        }
        if _quickCardPlaceID != nil {
            closeQuickCard(restoreMapZoom: restoreMapZoom)
        }
    }

    func selectPlaceFromCarousel(placeID: UUID) {
        guard _detailPlaceID == nil else { return }
        cancelPendingQuickCardPresentation()
        cancelPendingMapZoomRestore()
        cancelPendingMapFocus()
        let targetPlace = placeForInteraction(placeID)
        let focusPlace = targetPlace.flatMap { place in
            shouldFocusQuickCard(place: place) ? place : nil
        }
        withAnimation(quickCardPresentationAnimation) {
            openQuickCard(
                placeID: placeID,
                keepMarkerActions: true,
                showPanel: true,
                focusPlace: focusPlace
            )
        }
    }

    func openDetailForCurrentQuickCard() {
        guard let currentBottomCardPlaceID = _quickCardPlaceID ?? _expiredCardPlaceID else {
            return
        }
        guard placeForInteraction(currentBottomCardPlaceID) != nil else {
            mutateInteractionState {
                _quickCardPlaceID = nil
                _expiredCardPlaceID = nil
                _temporaryExpiredMarkerPlaceID = nil
                _selectedPlaceID = nil
                _markerActionPlaceID = nil
                _detailPlaceID = nil
                _forcedExpandedPlaceID = nil
            }
            return
        }
        mutateInteractionState {
            _detailPlaceID = currentBottomCardPlaceID
            _selectedPlaceID = currentBottomCardPlaceID
            _markerActionPlaceID = nil
            _quickCardPlaceID = nil
            _expiredCardPlaceID = nil
            _temporaryExpiredMarkerPlaceID = nil
        }
    }

    func closeDetail() {
        mutateInteractionState {
            _detailPlaceID = nil
        }
    }

    func toggleSideDrawerPanel() {
        if isSideDrawerOpen {
            closeSideDrawerPanel()
            return
        }
        cancelPendingMapZoomRestore()
        withAnimation(sideDrawerAnimation) {
            if !isSideDrawerOpen {
                isSideDrawerOpen = true
            }
            if sideDrawerMenu != .favorites {
                sideDrawerMenu = .favorites
            }
            if isFavoriteDrawerOpen {
                isFavoriteDrawerOpen = false
            }
            if isThemePaletteOpen {
                isThemePaletteOpen = false
            }
        }
    }

    func closeSideDrawerPanel() {
        withAnimation(sideDrawerAnimation) {
            if isSideDrawerOpen {
                isSideDrawerOpen = false
            }
            if isFavoriteDrawerOpen {
                isFavoriteDrawerOpen = false
            }
            if sideDrawerMenu != .none {
                sideDrawerMenu = .none
            }
            if isThemePaletteOpen {
                isThemePaletteOpen = false
            }
        }
    }

    func closeSideDrawerBackdrop() {
        if isFavoriteDrawerOpen {
            withAnimation(favoriteDrawerCloseAnimation) {
                isFavoriteDrawerOpen = false
            }
            return
        }
        closeSideDrawerPanel()
    }

    func setSideDrawerMenu(_ menu: SideDrawerMenu) {
        withAnimation(sideDrawerAnimation) {
            if !isSideDrawerOpen {
                isSideDrawerOpen = true
            }
            if sideDrawerMenu != menu {
                sideDrawerMenu = menu
            }
            if menu != .favorites, isFavoriteDrawerOpen {
                isFavoriteDrawerOpen = false
            }
        }
    }

    func toggleThemePalette() {
        isThemePaletteOpen.toggle()
    }

    func setThemeScheme(_ scheme: String) {
        selectedThemeScheme = scheme
    }

    func setLanguage(_ code: String) {
        let all = ["zh-Hans", "en", "ja"]
        let resolved = all.contains(code) ? code : "ja"
        selectedLanguageCode = resolved
        L10n.setLanguageCode(resolved)
    }

    func cycleLanguage() {
        let all = ["zh-Hans", "en", "ja"]
        guard let index = all.firstIndex(of: selectedLanguageCode) else {
            setLanguage(all[0])
            return
        }
        let next = all[(index + 1) % all.count]
        setLanguage(next)
    }

    func openFavoriteDrawer() {
        withAnimation(favoriteDrawerOpenAnimation) {
            isSideDrawerOpen = true
            sideDrawerMenu = .favorites
            favoriteFilter = .all
            isFavoriteDrawerOpen = true
        }
    }

    func closeFavoriteDrawer() {
        withAnimation(favoriteDrawerCloseAnimation) {
            isFavoriteDrawerOpen = false
        }
    }

    func setFavoriteFilter(_ filter: FavoriteDrawerFilter) {
        favoriteFilter = filter
    }

    func setMapCategoryFilter(_ filter: MapPlaceCategoryFilter) {
        mapCategoryFilter = filter
        reconcileSelectionForMapFilter()
    }

    func clearLocalData() {
        placeStateStore.clearAll()
        bumpPlaceStateRevision()
        placeStampStore.clearAll()
        placeDecorationStore.retainOnly(placeID: nil)

        startReminderSyncTask?.cancel()
        startReminderSyncTask = nil
        nearbyReminderSyncTask?.cancel()
        nearbyReminderSyncTask = nil
        startNotificationEnabled = false
        nearbyNotificationEnabled = false

        Task { [weak self] in
            guard let self else { return }
            await self.removePendingNotifications(withPrefix: self.startReminderNotificationPrefix)
            await self.removePendingNotifications(withPrefix: self.nearbyReminderNotificationPrefix)
        }

        favoriteFilter = .all
        mapCategoryFilter = .all
        cancelPendingQuickCardPresentation()
        cancelPendingMapZoomRestore()
        cancelPendingMapFocus()
        mutateInteractionState {
            _selectedPlaceID = nil
            _markerActionPlaceID = nil
            _quickCardPlaceID = nil
            _expiredCardPlaceID = nil
            _temporaryExpiredMarkerPlaceID = nil
            _detailPlaceID = nil
            _forcedExpandedPlaceID = nil
        }
        markerEntriesCacheKey = nil
        markerEntriesCache = []
        markerEntriesIndexByID = [:]
        presentTopNotice(message: L10n.SideDrawer.localDataClearedNotice)
    }

    func mapMarkerEntries() -> [MapMarkerEntry] {
        let isDetailVisible = _detailPlaceID != nil
        let now = Date()
        let overlapRegion = normalizedRegion(lastKnownMapRegion ?? mapCameraPosition.region) ?? MKCoordinateRegion(
            center: resolvedCenter,
            span: defaultMapSpan
        )
        let visibleMenuState: PlaceState? = {
            guard !isDetailVisible, let placeID = _markerActionPlaceID else {
                return nil
            }
            return placeStateStore.state(for: placeID)
        }()

        let cacheKey = MarkerEntriesCacheKey(
            placesRevision: placesRevision,
            statusTimeBucket: Int64(floor(now.timeIntervalSince1970 / markerStatusCacheTimeBucketSeconds)),
            filter: mapCategoryFilter,
            selectedPlaceID: _selectedPlaceID,
            markerActionPlaceID: _markerActionPlaceID,
            forcedExpandedPlaceID: _forcedExpandedPlaceID,
            temporaryExpiredMarkerPlaceID: _temporaryExpiredMarkerPlaceID,
            isDetailVisible: isDetailVisible,
            visibleMenuState: visibleMenuState,
            overlapCenterLatE3: Int((overlapRegion.center.latitude * 1_000).rounded()),
            overlapSpanLatE4: Int((overlapRegion.span.latitudeDelta * 10_000).rounded()),
            overlapSpanLngE4: Int((overlapRegion.span.longitudeDelta * 10_000).rounded())
        )

        if markerEntriesCacheKey == cacheKey {
            return markerEntriesCache
        }

        if let previousKey = markerEntriesCacheKey,
           let incrementallyUpdated = incrementallyUpdatedMarkerEntries(from: previousKey, to: cacheKey) {
            markerEntriesCacheKey = cacheKey
            markerEntriesCache = incrementallyUpdated
            return incrementallyUpdated
        }

        let places = mapPlaces()
        let clusters = markerClusters(from: places, region: overlapRegion)
        let forcedExpandedPlaceID = _forcedExpandedPlaceID
        let forcedPlace = forcedExpandedPlaceID.flatMap { placeForInteraction($0) }
        var entries = clusters.compactMap { cluster -> MapMarkerEntry? in
            let renderedPlace: HePlace
            let clusterCount: Int
            if let forcedExpandedPlaceID,
               cluster.memberIDs.contains(forcedExpandedPlaceID),
               let forcedPlace {
                // Forced expansion: render only the target place for this overlap group.
                renderedPlace = forcedPlace
                clusterCount = 1
            } else {
                renderedPlace = cluster.anchor
                clusterCount = cluster.count
            }

            let isCluster = clusterCount > 1
            let isMenuVisible = _markerActionPlaceID == renderedPlace.id && !isDetailVisible
            let isEnded = isPlaceEndedFast(renderedPlace, now: now)
            return MapMarkerEntry(
                id: renderedPlace.id,
                name: renderedPlace.name,
                coordinate: renderedPlace.coordinate,
                heType: renderedPlace.heType,
                isEnded: isEnded,
                isSelected: _selectedPlaceID == renderedPlace.id,
                isCluster: isCluster,
                clusterCount: clusterCount,
                isTemporary: false,
                isMenuVisible: isMenuVisible,
                menuPlaceState: isMenuVisible ? placeState(for: renderedPlace.id) : nil
            )
        }
        appendTemporaryExpiredMarkerIfNeeded(to: &entries, isDetailVisible: isDetailVisible)

        markerEntriesCacheKey = cacheKey
        markerEntriesCache = entries
        markerEntriesIndexByID = Dictionary(
            uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) }
        )
        return entries
    }

    private func incrementallyUpdatedMarkerEntries(
        from previousKey: MarkerEntriesCacheKey,
        to nextKey: MarkerEntriesCacheKey
    ) -> [MapMarkerEntry]? {
        guard previousKey.placesRevision == nextKey.placesRevision,
              previousKey.statusTimeBucket == nextKey.statusTimeBucket,
              previousKey.filter == nextKey.filter,
              previousKey.overlapCenterLatE3 == nextKey.overlapCenterLatE3,
              previousKey.overlapSpanLatE4 == nextKey.overlapSpanLatE4,
              previousKey.overlapSpanLngE4 == nextKey.overlapSpanLngE4,
              !markerEntriesCache.isEmpty,
              !markerEntriesIndexByID.isEmpty else {
            return nil
        }

        // Selection/menu/forced-expanded target changes may alter overlap rendering ownership.
        guard previousKey.selectedPlaceID == nextKey.selectedPlaceID,
              previousKey.markerActionPlaceID == nextKey.markerActionPlaceID,
              previousKey.forcedExpandedPlaceID == nextKey.forcedExpandedPlaceID,
              previousKey.temporaryExpiredMarkerPlaceID == nextKey.temporaryExpiredMarkerPlaceID else {
            return nil
        }

        let currentMenuPlaceID = nextKey.isDetailVisible ? nil : nextKey.markerActionPlaceID
        let affectedPlaceIDs = Set([
            previousKey.selectedPlaceID,
            nextKey.selectedPlaceID,
            previousKey.markerActionPlaceID,
            nextKey.markerActionPlaceID
        ].compactMap { $0 })

        guard !affectedPlaceIDs.isEmpty else {
            return markerEntriesCache
        }

        var updated = markerEntriesCache
        for placeID in affectedPlaceIDs {
            guard let index = markerEntriesIndexByID[placeID] else {
                continue
            }
            let previousEntry = updated[index]
            let nextIsSelected = (nextKey.selectedPlaceID == placeID)
            let nextIsMenuVisible = (currentMenuPlaceID == placeID)
            let nextMenuState: PlaceState? = nextIsMenuVisible
                ? (nextKey.visibleMenuState ?? placeStateStore.state(for: placeID))
                : nil

            if previousEntry.isSelected == nextIsSelected &&
                previousEntry.isMenuVisible == nextIsMenuVisible &&
                previousEntry.menuPlaceState == nextMenuState {
                continue
            }

            updated[index] = MapMarkerEntry(
                id: previousEntry.id,
                name: previousEntry.name,
                coordinate: previousEntry.coordinate,
                heType: previousEntry.heType,
                isEnded: previousEntry.isEnded,
                isSelected: nextIsSelected,
                isCluster: previousEntry.isCluster,
                clusterCount: previousEntry.clusterCount,
                isTemporary: previousEntry.isTemporary,
                isMenuVisible: nextIsMenuVisible,
                menuPlaceState: nextMenuState
            )
        }
        return updated
    }

    private func appendTemporaryExpiredMarkerIfNeeded(
        to entries: inout [MapMarkerEntry],
        isDetailVisible: Bool
    ) {
        guard let temporaryMarkerPlaceID = _temporaryExpiredMarkerPlaceID,
              entries.contains(where: { $0.id == temporaryMarkerPlaceID }) == false,
              let place = place(for: temporaryMarkerPlaceID) else {
            return
        }
        let isMenuVisible = _markerActionPlaceID == temporaryMarkerPlaceID && !isDetailVisible
        entries.append(
            MapMarkerEntry(
                id: place.id,
                name: place.name,
                coordinate: place.coordinate,
                heType: place.heType,
                isEnded: true,
                isSelected: _selectedPlaceID == place.id,
                isCluster: false,
                clusterCount: 1,
                isTemporary: true,
                isMenuVisible: isMenuVisible,
                menuPlaceState: isMenuVisible ? placeState(for: place.id) : nil
            )
        )
    }

    func filteredFavoritePlaces() -> [HePlace] {
        let snapshot = sideDrawerSnapshot()
        switch favoriteFilter {
        case .all:
            return snapshot.favoritesAll
        case .planned:
            return snapshot.favoritesPlanned
        case .checked:
            return snapshot.favoritesChecked
        }
    }

    func favoriteFilterCount(_ filter: FavoriteDrawerFilter) -> Int {
        sideDrawerSnapshot().favoriteCounts[filter] ?? 0
    }

    func mapCategoryFilterCount(_ filter: MapPlaceCategoryFilter) -> Int {
        sideDrawerSnapshot().mapCategoryCounts[filter] ?? 0
    }

    func mapCategoryFiltersForSidebar() -> [MapPlaceCategoryFilter] {
        sideDrawerSnapshot().mapCategoryFilters
    }

    func mapCategoryFilterTitle(_ filter: MapPlaceCategoryFilter) -> String {
        switch filter.rawValue {
        case MapPlaceCategoryFilter.all.rawValue:
            return L10n.Calendar.categoryAll
        case MapPlaceCategoryFilter.hanabi.rawValue:
            return L10n.Calendar.categoryHanabi
        case MapPlaceCategoryFilter.matsuri.rawValue:
            return L10n.Calendar.categoryMatsuri
        case MapPlaceCategoryFilter.nature.rawValue:
            return L10n.Calendar.categoryNature
        case MapPlaceCategoryFilter.other.rawValue:
            return L10n.Calendar.categoryOther
        case MapPlaceCategoryFilter.sakura.rawValue:
            return L10n.Calendar.categorySakura
        case MapPlaceCategoryFilter.momiji.rawValue:
            return L10n.Calendar.categoryMomiji
        default:
            return filter.rawValue.localizedCapitalized
        }
    }

    private func sideDrawerSnapshot() -> SideDrawerSnapshot {
        let usesRenderedSource = places.isEmpty
        let sourceRevision = usesRenderedSource ? placesRevision : allPlacesRevision
        let cacheKey = SideDrawerSnapshotCacheKey(
            sourceRevision: sourceRevision,
            usesRenderedSource: usesRenderedSource,
            placeStateRevision: placeStateRevision
        )
        if sideDrawerSnapshotCacheKey == cacheKey, let cached = sideDrawerSnapshotCache {
            return cached
        }

        let source = usesRenderedSource ? renderedPlaces : places
        let interactive = source.filter { isPlaceInteractionEnabled($0) }
        let favoriteTuples: [(place: HePlace, isCheckedIn: Bool)] = interactive.compactMap { place in
            let state = placeStateStore.state(for: place.id)
            guard state.isFavorite else {
                return nil
            }
            return (place, state.isCheckedIn)
        }

        let snapshotNow = Date()
        let favoritesAll = favoriteTuples
            .map(\.place)
            .sorted { lhs, rhs in
                isFavoriteDrawerHigherPriority(lhs, rhs, now: snapshotNow)
            }

        let checkedInByID = Dictionary(uniqueKeysWithValues: favoriteTuples.map { ($0.place.id, $0.isCheckedIn) })
        let favoritesPlanned = favoritesAll.filter { !(checkedInByID[$0.id] ?? false) }
        let favoritesChecked = favoritesAll.filter { checkedInByID[$0.id] ?? false }
        let favoriteCounts: [FavoriteDrawerFilter: Int] = [
            .all: favoritesAll.count,
            .planned: favoritesPlanned.count,
            .checked: favoritesChecked.count
        ]

        var mapCategoryCounts: [MapPlaceCategoryFilter: Int] = [.all: source.count]
        for place in source {
            let filter = MapPlaceCategoryFilter(rawValue: place.heType.rawValue)
            mapCategoryCounts[filter, default: 0] += 1
        }

        let typeIDs = Set(source.map { $0.heType.rawValue })
        let preferredOrder = [
            MapPlaceCategoryFilter.hanabi.rawValue,
            MapPlaceCategoryFilter.matsuri.rawValue,
            MapPlaceCategoryFilter.sakura.rawValue,
            MapPlaceCategoryFilter.momiji.rawValue,
            MapPlaceCategoryFilter.nature.rawValue,
            MapPlaceCategoryFilter.other.rawValue
        ]
        let ordered = preferredOrder.filter { typeIDs.contains($0) }
        let remaining = typeIDs.subtracting(Set(ordered)).sorted()
        let categoryFilters = (ordered + remaining).map(MapPlaceCategoryFilter.init(rawValue:))
        let mapCategoryFilters = [.all] + categoryFilters

        let snapshot = SideDrawerSnapshot(
            favoritesAll: favoritesAll,
            favoritesPlanned: favoritesPlanned,
            favoritesChecked: favoritesChecked,
            favoriteCounts: favoriteCounts,
            mapCategoryCounts: mapCategoryCounts,
            mapCategoryFilters: mapCategoryFilters
        )
        sideDrawerSnapshotCacheKey = cacheKey
        sideDrawerSnapshotCache = snapshot
        return snapshot
    }

    private func invalidateSideDrawerSnapshotCache() {
        sideDrawerSnapshotCacheKey = nil
        sideDrawerSnapshotCache = nil
    }

    private func bumpPlaceStateRevision() {
        placeStateRevision &+= 1
        invalidateSideDrawerSnapshotCache()
    }

    func openQuickFromDrawer(placeID: UUID) {
        openQuickFromExternalNavigation(placeID: placeID, closeDrawer: true)
    }

    func openQuickFromCalendar(placeID: UUID) {
        openQuickFromExternalNavigation(placeID: placeID, closeDrawer: false)
    }

    func toggleStartNotification() {
        if startNotificationEnabled {
            withAnimation(TsugieVisuals.notificationToggleAnimation) {
                startNotificationEnabled = false
            }
            startReminderSyncTask?.cancel()
            startReminderSyncTask = nil
            let prefix = startReminderNotificationPrefix
            Task { [weak self] in
                await self?.removePendingNotifications(withPrefix: prefix)
            }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.ensureNotificationAuthorization()
            guard !Task.isCancelled else { return }
            guard granted else {
                await MainActor.run {
                    if self.startNotificationEnabled {
                        withAnimation(TsugieVisuals.notificationToggleAnimation) {
                            self.startNotificationEnabled = false
                        }
                    }
                }
                return
            }
            await MainActor.run {
                withAnimation(TsugieVisuals.notificationToggleAnimation) {
                    self.startNotificationEnabled = true
                }
                self.scheduleStartReminderSync()
            }
        }
    }

    private func openQuickFromExternalNavigation(placeID: UUID, closeDrawer: Bool) {
        guard let place = placeForInteraction(placeID) else {
            return
        }
        cancelPendingQuickCardPresentation()
        cancelPendingMapZoomRestore()
        cancelPendingMapFocus()
        markAnnotationTapCooldown(0.45)
        if closeDrawer {
            closeSideDrawerPanel()
        }
        if eventStatus(for: place) == .ended {
            withAnimation(quickCardPresentationAnimation) {
                openExpiredCard(place: place)
            }
            return
        }
        withAnimation(quickCardPresentationAnimation) {
            openQuickCard(placeID: placeID, keepMarkerActions: true, showPanel: true)
        }
    }

    private func openExpiredCard(place: HePlace) {
        resetMapCategoryFilterIfNeeded(for: place)
        ensureRenderedContains(place)
        let currentPlaceState = placeStateStore.state(for: place.id)
        if !currentPlaceState.isFavorite && !currentPlaceState.isCheckedIn {
            placeStampStore.refreshTransientStamp(for: place.id, heType: place.heType)
        }
        cancelPendingMapZoomRestore()
        let overlapRegion = normalizedRegion(lastKnownMapRegion ?? mapCameraPosition.region) ?? MKCoordinateRegion(
            center: resolvedCenter,
            span: defaultMapSpan
        )
        let shouldForceExpandedMarker = isOverlapClusterPlace(place, region: overlapRegion)
        let focusedRegion = nonExpandingFocusedRegion(for: place)
        mutateInteractionState {
            _selectedPlaceID = place.id
            _markerActionPlaceID = place.id
            _detailPlaceID = nil
            _quickCardPlaceID = nil
            _expiredCardPlaceID = place.id
            _temporaryExpiredMarkerPlaceID = place.id
            _forcedExpandedPlaceID = shouldForceExpandedMarker ? place.id : nil
            if let normalizedFocusedRegion = normalizedRegion(focusedRegion) {
                mapCameraPosition = .region(normalizedFocusedRegion)
                lastKnownMapRegion = normalizedFocusedRegion
                registerProgrammaticCameraChangeTarget(
                    normalizedFocusedRegion,
                    source: "openExpiredCardFocus"
                )
            }
        }
    }

    func toggleNearbyNotification() {
        if nearbyNotificationEnabled {
            withAnimation(TsugieVisuals.notificationToggleAnimation) {
                nearbyNotificationEnabled = false
            }
            nearbyReminderSyncTask?.cancel()
            nearbyReminderSyncTask = nil
            let prefix = nearbyReminderNotificationPrefix
            Task { [weak self] in
                await self?.removePendingNotifications(withPrefix: prefix)
            }
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let granted = await self.ensureNotificationAuthorization()
            guard !Task.isCancelled else { return }
            guard granted else {
                await MainActor.run {
                    if self.nearbyNotificationEnabled {
                        withAnimation(TsugieVisuals.notificationToggleAnimation) {
                            self.nearbyNotificationEnabled = false
                        }
                    }
                }
                return
            }
            await MainActor.run {
                withAnimation(TsugieVisuals.notificationToggleAnimation) {
                    self.nearbyNotificationEnabled = true
                }
                self.scheduleNearbyReminderSync()
            }
        }
    }

    func resetToCurrentLocation() {
        cancelPendingMapZoomRestore()
        cancelPendingQuickCardPresentation()
        cancelPendingMapFocus()
        focusMapOnCurrentLocationAnchor(reason: "userResetLocationImmediate")
        reloadNearbyPlacesAroundCurrentLocation(userInitiated: true)
    }

    private func focusMapOnCurrentLocationAnchor(reason: String) {
        let anchor = resolvedCenter
        let targetRegion = MKCoordinateRegion(
            center: anchor,
            span: defaultMapSpan
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            setProgrammaticMapPosition(
                .region(targetRegion),
                source: "resetLocationImmediate",
                suppressionWindow: 0.35
            )
        }
        debugLog("focusMapOnCurrentLocationAnchor reason=\(reason)")
    }

    private func scheduleStartReminderSync() {
        startReminderSyncTask?.cancel()
        startReminderSyncTask = Task { [weak self] in
            await self?.syncStartReminderNotifications()
        }
    }

    private func scheduleNearbyReminderSync() {
        nearbyReminderSyncTask?.cancel()
        nearbyReminderSyncTask = Task { [weak self] in
            await self?.syncNearbyReminderNotifications()
        }
    }

    private func syncStartReminderNotifications() async {
        guard startNotificationEnabled else {
            return
        }
        let now = Date()
        let candidates = startReminderCandidates(now: now)
        await syncNotificationCandidates(
            candidates,
            prefix: startReminderNotificationPrefix,
            title: L10n.Notification.startingSoonTitle
        )
    }

    private func syncNearbyReminderNotifications() async {
        guard nearbyNotificationEnabled else {
            return
        }
        let now = Date()
        let candidates = nearbyReminderCandidates(now: now)
        await syncNotificationCandidates(
            candidates,
            prefix: nearbyReminderNotificationPrefix,
            title: L10n.Notification.startingSoonTitle
        )
    }

    private func startReminderCandidates(now: Date) -> [LocalNotificationCandidate] {
        var seen = Set<String>()
        let sorted = favoritePlaces().compactMap { place -> LocalNotificationCandidate? in
            let snapshot = eventSnapshot(for: place, now: now)
            guard snapshot.status == .upcoming,
                  let startDate = snapshot.startDate else {
                return nil
            }
            let identifier = notificationIdentifier(
                prefix: startReminderNotificationPrefix,
                placeID: place.id,
                startDate: startDate
            )
            guard seen.insert(identifier).inserted else {
                return nil
            }
            return LocalNotificationCandidate(
                identifier: identifier,
                triggerDate: resolvedReminderTriggerDate(startDate: startDate, now: now),
                body: place.name
            )
        }
        .sorted { lhs, rhs in
            lhs.triggerDate < rhs.triggerDate
        }

        return Array(sorted.prefix(maxStartReminderCount))
    }

    private func nearbyReminderCandidates(now: Date) -> [LocalNotificationCandidate] {
        var seen = Set<String>()
        let sorted = nearbyPlaces(now: now, limit: maxNearbyReminderCount * 3).compactMap { place -> LocalNotificationCandidate? in
            if placeState(for: place.id).isFavorite {
                return nil
            }
            let snapshot = eventSnapshot(for: place, now: now)
            guard snapshot.status == .upcoming,
                  let startDate = snapshot.startDate else {
                return nil
            }
            let startDelta = startDate.timeIntervalSince(now)
            guard startDelta <= nearbyReminderLookahead else {
                return nil
            }
            let identifier = notificationIdentifier(
                prefix: nearbyReminderNotificationPrefix,
                placeID: place.id,
                startDate: startDate
            )
            guard seen.insert(identifier).inserted else {
                return nil
            }
            return LocalNotificationCandidate(
                identifier: identifier,
                triggerDate: resolvedReminderTriggerDate(startDate: startDate, now: now),
                body: place.name
            )
        }
        .sorted { lhs, rhs in
            lhs.triggerDate < rhs.triggerDate
        }

        return Array(sorted.prefix(maxNearbyReminderCount))
    }

    private func resolvedReminderTriggerDate(startDate: Date, now: Date) -> Date {
        let target = startDate.addingTimeInterval(-startReminderLeadTime)
        let minimum = now.addingTimeInterval(minimumNotificationLeadTime)
        return target > minimum ? target : minimum
    }

    private func notificationIdentifier(prefix: String, placeID: UUID, startDate: Date) -> String {
        "\(prefix)\(placeID.uuidString).\(Int(startDate.timeIntervalSince1970.rounded()))"
    }

    private func syncNotificationCandidates(
        _ candidates: [LocalNotificationCandidate],
        prefix: String,
        title: String
    ) async {
        let center = UNUserNotificationCenter.current()
        let pendingIDs = await center.pendingNotificationIDs()
        let deliveredIDs = await center.deliveredNotificationIDs()
        let pendingForPrefix = pendingIDs.filter { $0.hasPrefix(prefix) }
        let desiredIDs = Set(candidates.map(\.identifier))
        let stalePending = pendingForPrefix.subtracting(desiredIDs)
        if !stalePending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stalePending))
        }
        let existing = pendingIDs.union(deliveredIDs)
        for candidate in candidates where !existing.contains(candidate.identifier) {
            await scheduleLocalNotification(candidate, title: title)
        }
    }

    private func scheduleLocalNotification(_ candidate: LocalNotificationCandidate, title: String) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = candidate.body
        content.sound = .default
        let triggerDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: candidate.triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: candidate.identifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            debugLog("scheduleLocalNotification failed id=\(candidate.identifier) error=\(error.localizedDescription)")
        }
    }

    private func removePendingNotifications(withPrefix prefix: String) async {
        guard !prefix.isEmpty else {
            return
        }
        let center = UNUserNotificationCenter.current()
        let pending = (await center.pendingNotificationIDs()).filter { $0.hasPrefix(prefix) }
        if !pending.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(pending))
        }
    }

    private func ensureNotificationAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettingsAsync()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                debugLog("requestNotificationAuthorization failed error=\(error.localizedDescription)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func focus(on place: HePlace) {
        let targetRegion = nonExpandingFocusedRegion(for: place)
        withAnimation(.easeInOut(duration: 0.25)) {
            setProgrammaticMapPosition(.region(targetRegion))
        }
    }

    func handleDetailFocusTap(on place: HePlace) {
        if eventStatus(for: place) == .ended {
            cancelPendingQuickCardPresentation()
            cancelPendingMapZoomRestore()
            cancelPendingMapFocus()
            markAnnotationTapCooldown(0.45)
            withAnimation(quickCardPresentationAnimation) {
                openExpiredCard(place: place)
            }
            return
        }
        focus(on: place)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            closeDetail()
        }
    }

    func eventStatus(for place: HePlace, now: Date = Date()) -> EventStatus {
        EventStatusResolver.resolve(startAt: place.startAt, endAt: place.endAt, now: now)
    }

    private func isPlaceEndedFast(_ place: HePlace, now: Date) -> Bool {
        guard let startAt = place.startAt else {
            return false
        }
        if now < startAt {
            return false
        }
        if let endAt = place.endAt,
           endAt >= startAt,
           now <= endAt {
            return false
        }
        return true
    }

    func eventSnapshot(for place: HePlace, now: Date? = nil) -> EventStatusSnapshot {
        EventStatusResolver.snapshot(startAt: place.startAt, endAt: place.endAt, now: now ?? Date())
    }

    func quickProgress(for place: HePlace, now: Date? = nil) -> Double? {
        let snapshot = eventSnapshot(for: place, now: now)
        switch snapshot.status {
        case .ongoing:
            return snapshot.progress
        case .upcoming:
            return snapshot.waitProgress
        case .ended:
            return 1
        case .unknown:
            return nil
        }
    }

    func quickMetaText(for place: HePlace, now: Date? = nil) -> String {
        let resolvedNow = now ?? Date()
        let snapshot = eventSnapshot(for: place, now: resolvedNow)
        return "\(distanceText(for: place)) ・ \(quickStartDateText(for: snapshot, now: resolvedNow))"
    }

    func timeRangeText(for place: HePlace, now: Date? = nil) -> String {
        let snapshot = eventSnapshot(for: place, now: now)
        guard snapshot.status != .unknown else {
            return L10n.Common.unknownTime
        }
        return L10n.Common.timeRange(snapshot.startLabel, snapshot.endLabel)
    }

    func detailOpenHoursText(for place: HePlace, now: Date? = nil) -> String {
        if let openHours = place.openHours, !openHours.isEmpty {
            return openHours
        }
        return L10n.Common.openHours(timeRangeText(for: place, now: now))
    }

    func distanceText(for place: HePlace) -> String {
        let meters = max(place.distanceMeters, 0)
        if meters < 1_000 {
            return "\(Int(max(80, round(meters))))m"
        }

        let km = meters / 1_000
        return "\(km.formatted(.number.locale(selectedLanguageLocale).precision(.fractionLength(1))))km"
    }

    func quickHintText(for place: HePlace) -> String {
        place.hint
    }

    func placeState(for placeID: UUID) -> PlaceState {
        placeStateStore.state(for: placeID)
    }

    func stampPresentation(for place: HePlace) -> PlaceStampPresentation? {
        stampPresentation(for: place.id, heType: place.heType)
    }

    func stampPresentation(for placeID: UUID, heType: HeType) -> PlaceStampPresentation? {
        let state = placeStateStore.state(for: placeID)
        return placeStampStore.presentation(for: placeID, heType: heType, state: state)
    }

    func markerDecorationPresentation(for placeID: UUID, heType: HeType) -> PlaceDecorationPresentation? {
        guard _selectedPlaceID == placeID || _markerActionPlaceID == placeID else {
            return nil
        }
        return placeDecorationStore.presentation(for: placeID, heType: heType)
    }

    func toggleFavorite(for placeID: UUID) {
        let nextState = placeStateStore.toggleFavorite(for: placeID)
        bumpPlaceStateRevision()
        prewarmSideDrawerSnapshotForLaunch()
        if nextState.isFavorite, let place = place(for: placeID) {
            placeStampStore.lockStampIfNeeded(for: placeID, heType: place.heType)
        }
        objectWillChange.send()
        if startNotificationEnabled {
            scheduleStartReminderSync()
        }
        if nearbyNotificationEnabled {
            scheduleNearbyReminderSync()
        }
    }

    func toggleCheckedIn(for placeID: UUID) {
        if let place = place(for: placeID) {
            let snapshot = eventSnapshot(for: place, now: now)
            if snapshot.status == .upcoming {
                presentTopNotice(message: L10n.Home.checkInBlockedUpcoming)
                return
            }
        }
        let nextState = placeStateStore.toggleCheckedIn(for: placeID)
        bumpPlaceStateRevision()
        prewarmSideDrawerSnapshotForLaunch()
        if let place = place(for: placeID) {
            if nextState.isFavorite {
                placeStampStore.lockStampIfNeeded(for: placeID, heType: place.heType)
            }
            if nextState.isCheckedIn {
                // Re-sample decoration on every check-in action.
                _ = placeDecorationStore.resamplePresentation(for: placeID, heType: place.heType)
                mutateInteractionState {
                    _selectedPlaceID = placeID
                    if _detailPlaceID == nil {
                        _markerActionPlaceID = placeID
                    }
                }
                return
            }

            // Clearing check-in should clear current decoration so next check-in can re-randomize.
            placeDecorationStore.clearPresentation(for: placeID)
        }
        if _selectedPlaceID == placeID, _detailPlaceID == nil {
            mutateInteractionState {
                _markerActionPlaceID = placeID
            }
            return
        }
        objectWillChange.send()
    }

    func favoritePlaces() -> [HePlace] {
        sideDrawerSnapshot().favoritesAll
    }

    func fastestFavoritePlaces(now: Date = Date(), limit: Int = 2) -> [HePlace] {
        let clampedLimit = max(1, limit)
        let ranked = favoritePlaces().compactMap { place -> (place: HePlace, statusRank: Int, startDelta: TimeInterval)? in
            let snapshot = eventSnapshot(for: place, now: now)
            switch snapshot.status {
            case .ongoing:
                return (place, 0, 0)
            case .upcoming:
                guard let startDate = snapshot.startDate else {
                    return nil
                }
                return (place, 1, max(startDate.timeIntervalSince(now), 0))
            case .ended, .unknown:
                return nil
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.statusRank != rhs.statusRank {
                    return lhs.statusRank < rhs.statusRank
                }
                if lhs.startDelta != rhs.startDelta {
                    return lhs.startDelta < rhs.startDelta
                }
                if lhs.place.distanceMeters != rhs.place.distanceMeters {
                    return lhs.place.distanceMeters < rhs.place.distanceMeters
                }
                return lhs.place.name.localizedStandardCompare(rhs.place.name) == .orderedAscending
            }
            .prefix(clampedLimit)
            .map(\.place)
    }

    func fastestFavoriteIntroText(now: Date = Date()) -> String {
        guard let firstPlace = fastestFavoritePlaces(now: now, limit: 1).first else {
            if hasEndedFavoritesToday(now: now) {
                return L10n.SideDrawer.favoritesFastestHintTodayEnded
            }
            return L10n.SideDrawer.favoritesFastestHintOther
        }

        let snapshot = eventSnapshot(for: firstPlace, now: now)
        let calendar = Calendar.current
        switch snapshot.status {
        case .ongoing:
            return L10n.SideDrawer.favoritesFastestHintToday
        case .upcoming:
            guard let startDate = snapshot.startDate else {
                return L10n.SideDrawer.favoritesFastestHintOther
            }
            if calendar.isDateInToday(startDate) {
                return L10n.SideDrawer.favoritesFastestHintTodayLater
            }
            let dayGap = daysUntil(date: startDate, from: now)
            if dayGap <= 7 {
                return L10n.SideDrawer.favoritesFastestHintWithinWeek(days: max(dayGap, 1))
            }
            if dayGap <= 30 {
                let weeks = max(Int(ceil(Double(dayGap) / 7.0)), 1)
                return L10n.SideDrawer.favoritesFastestHintWithinMonth(weeks: weeks)
            }
            return L10n.SideDrawer.favoritesFastestHintOther
        case .ended:
            if let referenceDate = snapshot.endDate ?? snapshot.startDate,
               calendar.isDateInToday(referenceDate) {
                return L10n.SideDrawer.favoritesFastestHintTodayEnded
            }
            return L10n.SideDrawer.favoritesFastestHintOther
        case .unknown:
            return L10n.SideDrawer.favoritesFastestHintOther
        }
    }

    func place(for placeID: UUID) -> HePlace? {
        if let matched = places.first(where: { $0.id == placeID }) {
            return matched
        }
        return renderedPlaces.first(where: { $0.id == placeID })
            ?? nearbyRecommendationPlaces.first(where: { $0.id == placeID })
    }

    private func placeForInteraction(_ placeID: UUID, now: Date = Date()) -> HePlace? {
        guard let place = place(for: placeID),
              isPlaceInteractionEnabled(place, now: now) else {
            return nil
        }
        return place
    }

    func focusForBottomCard(on place: HePlace) {
        let targetRegion = nonExpandingFocusedRegion(for: place)
        withAnimation(.easeOut(duration: 0.24)) {
            setProgrammaticMapPosition(.region(targetRegion))
        }
    }

    func nearbyPlaces(now: Date = Date(), limit: Int = 10) -> [HePlace] {
        let sorted = nearbyRankedEntries(now: now)
        return Array(sorted.prefix(limit).map(\.place))
    }

    func nearbyCarouselItems(now: Date, limit: Int = 10) -> [NearbyCarouselItemModel] {
        nearbyRankedEntries(now: now).prefix(limit).map { entry in
            let place = entry.place
            return NearbyCarouselItemModel(
                id: place.id,
                name: place.name,
                snapshot: entry.snapshot,
                distanceText: distanceText(for: place),
                placeState: placeState(for: place.id),
                stamp: stampPresentation(for: place),
                endpointIconName: TsugieSmallIcon.assetName(for: place.heType)
            )
        }
    }

    private func nearbyRankedEntries(now: Date) -> [NearbyRankedEntry] {
        let nowBucket = Int64(floor(now.timeIntervalSince1970 / nearbyRankingTimeBucketSeconds))
        let cacheKey = NearbyRankingCacheKey(
            recommendationRevision: nearbyRecommendationRevision,
            nowBucket: nowBucket,
            filter: mapCategoryFilter
        )
        if nearbyRankingCacheKey == cacheKey {
            return nearbyRankingCache
        }

        let ranked = nearbyRecommendationSourcePlaces().compactMap { place -> NearbyRankedEntry? in
            let snapshot = eventSnapshot(for: place, now: now)
            guard snapshot.status != .ended else {
                return nil
            }
            return nearbyRecommendationSignal(for: place, snapshot: snapshot, now: now)
        }

        let sorted = ranked.sorted { lhs, rhs in
            let lhsUnknown = lhs.stage == 3
            let rhsUnknown = rhs.stage == 3
            if lhsUnknown != rhsUnknown {
                return !lhsUnknown
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.place.heType != rhs.place.heType {
                if lhs.place.heType == .hanabi { return true }
                if rhs.place.heType == .hanabi { return false }
            }
            if lhs.stage != rhs.stage {
                return lhs.stage < rhs.stage
            }
            if lhs.stageDelta != rhs.stageDelta {
                return lhs.stageDelta < rhs.stageDelta
            }
            if lhs.place.distanceMeters != rhs.place.distanceMeters {
                return lhs.place.distanceMeters < rhs.place.distanceMeters
            }
            if lhs.place.scaleScore != rhs.place.scaleScore {
                return lhs.place.scaleScore > rhs.place.scaleScore
            }
            return lhs.place.name.localizedStandardCompare(rhs.place.name) == .orderedAscending
        }

        nearbyRankingCacheKey = cacheKey
        nearbyRankingCache = sorted
        return sorted
    }

    func mapPlaces() -> [HePlace] {
        guard mapCategoryFilter != .all else {
            return renderedPlaces
        }
        return renderedPlaces.filter { $0.heType.rawValue == mapCategoryFilter.rawValue }
    }

    private func resetMapCategoryFilterIfNeeded(for place: HePlace) {
        guard mapCategoryFilter != .all, !isPlaceVisibleInMapCategoryFilter(place) else {
            return
        }
        setMapCategoryFilter(.all)
    }

    private func isPlaceVisibleInMapCategoryFilter(_ place: HePlace) -> Bool {
        guard mapCategoryFilter != .all else {
            return true
        }
        return place.heType.rawValue == mapCategoryFilter.rawValue
    }

    private func reconcileSelectionForMapFilter() {
        let visiblePlaceIDs = Set(mapPlaces().map(\.id))
        let nextDetailPlaceID = _detailPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextQuickCardPlaceID = _quickCardPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextExpiredCardPlaceID = _expiredCardPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextMarkerActionPlaceID = _markerActionPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextSelectedPlaceID = _selectedPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextForcedExpandedPlaceID = _forcedExpandedPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextTemporaryExpiredMarkerPlaceID = _temporaryExpiredMarkerPlaceID.flatMap {
            visiblePlaceIDs.contains($0) ? $0 : nil
        }

        let changed =
            nextDetailPlaceID != _detailPlaceID ||
            nextQuickCardPlaceID != _quickCardPlaceID ||
            nextExpiredCardPlaceID != _expiredCardPlaceID ||
            nextMarkerActionPlaceID != _markerActionPlaceID ||
            nextSelectedPlaceID != _selectedPlaceID ||
            nextForcedExpandedPlaceID != _forcedExpandedPlaceID ||
            nextTemporaryExpiredMarkerPlaceID != _temporaryExpiredMarkerPlaceID

        guard changed else {
            return
        }

        mutateInteractionState {
            _detailPlaceID = nextDetailPlaceID
            _quickCardPlaceID = nextQuickCardPlaceID
            _expiredCardPlaceID = nextExpiredCardPlaceID
            _markerActionPlaceID = nextMarkerActionPlaceID
            _selectedPlaceID = nextSelectedPlaceID
            _forcedExpandedPlaceID = nextForcedExpandedPlaceID
            _temporaryExpiredMarkerPlaceID = nextTemporaryExpiredMarkerPlaceID
        }
    }

    private func quickStartDateText(for snapshot: EventStatusSnapshot, now: Date) -> String {
        if snapshot.status == .ongoing {
            return L10n.Home.quickDateOngoingNow
        }

        if snapshot.status == .ended {
            return L10n.EventStatus.ended
        }

        if let endDate = snapshot.endDate, endDate <= now {
            return L10n.EventStatus.ended
        }

        guard let startDate = snapshot.startDate else {
            return L10n.Common.dateUnknown
        }

        if snapshot.status == .upcoming, Calendar.current.isDateInToday(startDate) {
            return L10n.Home.quickDateTodaySoon
        }

        return startDate.formatted(
            Date.FormatStyle()
                .year(.defaultDigits)
                .month(.twoDigits)
                .day(.twoDigits)
                .locale(selectedLanguageLocale)
        )
    }

    private func daysUntil(date: Date, from referenceDate: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: referenceDate)
        let targetDay = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0, 0)
    }

    private func hasEndedFavoritesToday(now: Date) -> Bool {
        let calendar = Calendar.current
        return favoritePlaces().contains { place in
            let snapshot = eventSnapshot(for: place, now: now)
            guard snapshot.status == .ended,
                  let referenceDate = snapshot.endDate ?? snapshot.startDate else {
                return false
            }
            return calendar.isDateInToday(referenceDate)
        }
    }

    private func scheduleAutoOpenIfNeeded() {
        guard autoOpenTask == nil, !hasAutoOpened else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.autoOpenTask = nil
            guard self._quickCardPlaceID == nil,
                  self._expiredCardPlaceID == nil,
                  self._detailPlaceID == nil,
                  !self.isCalendarPresented,
                  let target = self.recommendedPlace() else {
                return
            }
            self.focusForBottomCard(on: target)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                self.openQuickCard(placeID: target.id, keepMarkerActions: true)
            }
            self.hasAutoOpened = true
        }

        autoOpenTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: workItem)
    }

    private func recommendedPlace(now: Date = Date()) -> HePlace? {
        nearbyRankedEntries(now: now).first?.place
    }

    private func clusterTemporalScore(_ place: HePlace, now: Date) -> (stage: Int, delta: TimeInterval) {
        let snapshot = EventStatusResolver.snapshot(
            startAt: place.startAt,
            endAt: place.endAt,
            now: now
        )
        switch snapshot.status {
        case .ongoing:
            let remaining = max((snapshot.endDate ?? now).timeIntervalSince(now), 0)
            return (0, remaining)
        case .upcoming:
            let wait = max((snapshot.startDate ?? snapshot.endDate ?? now).timeIntervalSince(now), 0)
            return (1, wait)
        case .ended:
            let elapsed = max(now.timeIntervalSince(snapshot.endDate ?? snapshot.startDate ?? now), 0)
            return (2, elapsed)
        case .unknown:
            return (3, .greatestFiniteMagnitude)
        }
    }

    private func isEarlierForClusterAnchor(_ lhs: HePlace, _ rhs: HePlace, now: Date) -> Bool {
        let l = clusterTemporalScore(lhs, now: now)
        let r = clusterTemporalScore(rhs, now: now)
        if l.stage != r.stage {
            return l.stage < r.stage
        }
        if l.delta != r.delta {
            return l.delta < r.delta
        }
        if lhs.scaleScore != rhs.scaleScore {
            return lhs.scaleScore > rhs.scaleScore
        }
        if lhs.distanceMeters != rhs.distanceMeters {
            return lhs.distanceMeters < rhs.distanceMeters
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func isCloserAndEarlier(_ lhs: HePlace, _ rhs: HePlace) -> Bool {
        if lhs.distanceMeters != rhs.distanceMeters {
            return lhs.distanceMeters < rhs.distanceMeters
        }
        let lStart = lhs.startAt?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
        let rStart = rhs.startAt?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
        if lStart != rStart {
            return lStart < rStart
        }
        return lhs.scaleScore > rhs.scaleScore
    }

    private func isHigherPriority(_ lhs: HePlace, _ rhs: HePlace) -> Bool {
        let lhsToday = lhs.startAt.map(Calendar.current.isDateInToday) ?? false
        let rhsToday = rhs.startAt.map(Calendar.current.isDateInToday) ?? false
        if lhsToday != rhsToday {
            return lhsToday
        }
        if lhs.distanceMeters != rhs.distanceMeters {
            return lhs.distanceMeters < rhs.distanceMeters
        }
        if lhs.scaleScore != rhs.scaleScore {
            return lhs.scaleScore > rhs.scaleScore
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private func isFavoriteDrawerHigherPriority(_ lhs: HePlace, _ rhs: HePlace, now: Date) -> Bool {
        let lhsOngoing = eventStatus(for: lhs, now: now) == .ongoing
        let rhsOngoing = eventStatus(for: rhs, now: now) == .ongoing
        if lhsOngoing != rhsOngoing {
            return lhsOngoing
        }
        return isHigherPriority(lhs, rhs)
    }

    private func nearbyRecommendationSignal(
        for place: HePlace,
        snapshot: EventStatusSnapshot,
        now: Date
    ) -> NearbyRankedEntry {
        let distanceKm = max(place.distanceMeters, 0) / 1_000
        let spaceScore = Foundation.exp(-distanceKm / 5)
        let timeScore = nearbyTimeScore(snapshot: snapshot, now: now)
        let dynamicHeatScore = dynamicNearbyHeatScore(for: place, snapshot: snapshot, now: now)
        let dynamicSurpriseScore = dynamicNearbySurpriseScore(
            for: place,
            snapshot: snapshot,
            now: now,
            distanceKm: distanceKm
        )
        let ongoingNearBoost = nearbyOngoingProximityBoost(snapshot: snapshot, distanceKm: distanceKm)
        let imminentStartBoost = nearbyImminentUpcomingBoost(snapshot: snapshot, distanceKm: distanceKm, now: now)

        let categoryWeight: Double
        switch place.heType {
        case .hanabi:
            categoryWeight = 1.2
        case .matsuri:
            categoryWeight = 1.0
        case .nature:
            categoryWeight = 0.8
        case .other:
            categoryWeight = 1.0
        }

        let geoConfidencePenalty: Double = place.geoSource == "missing" || place.geoSource == "pref_center_fallback" ? 0.85 : 1.0
        let score = (
            0.33 * spaceScore +
            0.35 * timeScore +
            0.20 * dynamicHeatScore +
            0.12 * dynamicSurpriseScore +
            ongoingNearBoost +
            imminentStartBoost
        ) * categoryWeight * geoConfidencePenalty

        return NearbyRankedEntry(
            place: place,
            snapshot: snapshot,
            score: score,
            stage: nearbyStage(snapshot: snapshot),
            stageDelta: nearbyStageDelta(snapshot: snapshot, now: now)
        )
    }

    private func nearbyTimeScore(snapshot: EventStatusSnapshot, now: Date) -> Double {
        switch snapshot.status {
        case .ongoing:
            return 1.0
        case .upcoming:
            guard let startDate = snapshot.startDate else {
                return 0.08
            }
            let deltaHours = max(startDate.timeIntervalSince(now), 0) / 3_600
            if deltaHours < 3 {
                return 0.8
            }
            if deltaHours < 12 {
                return 0.6
            }
            if deltaHours < 24 {
                return 0.3
            }
            let deltaDays = deltaHours / 24
            let longHorizonDecayWindowDays = 14.0
            let longHorizonFloor = 0.03
            let decayed = 0.3 / (1 + max(deltaDays - 1, 0) / longHorizonDecayWindowDays)
            return max(longHorizonFloor, decayed)
        case .ended:
            return 0.05
        case .unknown:
            return 0.08
        }
    }

    private func nearbyStage(snapshot: EventStatusSnapshot) -> Int {
        switch snapshot.status {
        case .ongoing:
            return 0
        case .upcoming:
            return 1
        case .ended:
            return 2
        case .unknown:
            return 3
        }
    }

    private func nearbyStageDelta(snapshot: EventStatusSnapshot, now: Date) -> TimeInterval {
        switch snapshot.status {
        case .ongoing:
            return max((snapshot.endDate ?? now).timeIntervalSince(now), 0)
        case .upcoming:
            return max((snapshot.startDate ?? snapshot.endDate ?? now).timeIntervalSince(now), 0)
        case .ended:
            return max(now.timeIntervalSince(snapshot.endDate ?? snapshot.startDate ?? now), 0)
        case .unknown:
            return .greatestFiniteMagnitude
        }
    }

    private func dynamicNearbyHeatScore(for place: HePlace, snapshot: EventStatusSnapshot, now: Date) -> Double {
        let base = clampedUnit(Double(place.heatScore) / 100)
        guard let startAt = place.startAt else {
            return base * 0.92
        }

        let minimumDuration: TimeInterval = 2 * 3_600
        let defaultEnd = startAt.addingTimeInterval(minimumDuration)
        let endAt = max(place.endAt ?? defaultEnd, defaultEnd)

        let rampLeadWindow: TimeInterval = 36 * 3_600
        let rampStart = startAt.addingTimeInterval(-rampLeadWindow)

        if now <= rampStart {
            return base
        }

        if now < startAt {
            let total = max(startAt.timeIntervalSince(rampStart), 1)
            let progress = clampedUnit(now.timeIntervalSince(rampStart) / total)
            let preheatBoost = 0.16 * pow(progress, 1.08)
            return clampedUnit(base + preheatBoost)
        }

        if now <= endAt {
            let total = max(endAt.timeIntervalSince(startAt), 1)
            let progress = clampedUnit(now.timeIntervalSince(startAt) / total)
            let ongoingBoost = 0.28 - (0.10 * progress)
            return clampedUnit(base + ongoingBoost)
        }

        let coolDownWindow: TimeInterval = 6 * 3_600
        let decay = clampedUnit(now.timeIntervalSince(endAt) / coolDownWindow)
        let cooled = base + (0.12 * (1 - decay))
        if snapshot.status == .ended {
            return clampedUnit(max(cooled, 0.05))
        }
        return clampedUnit(cooled)
    }

    private func dynamicNearbySurpriseScore(
        for place: HePlace,
        snapshot: EventStatusSnapshot,
        now: Date,
        distanceKm: Double
    ) -> Double {
        let base = clampedUnit(Double(place.surpriseScore) / 100)
        let proximity = clampedUnit(Foundation.exp(-distanceKm / 3.5))

        switch snapshot.status {
        case .ongoing:
            return clampedUnit(base + 0.18 * proximity)
        case .upcoming:
            guard let startDate = snapshot.startDate else {
                return clampedUnit(base * 0.94)
            }
            let deltaHours = max(startDate.timeIntervalSince(now), 0) / 3_600
            if deltaHours <= 6 {
                let imminence = 1 - (deltaHours / 6)
                return clampedUnit(base + 0.03 + (0.14 * imminence * proximity))
            }
            if deltaHours <= 24 {
                return clampedUnit(base + 0.05 * proximity)
            }
            return base
        case .ended:
            return clampedUnit(base * 0.72)
        case .unknown:
            return clampedUnit(base * 0.88)
        }
    }

    private func nearbyOngoingProximityBoost(snapshot: EventStatusSnapshot, distanceKm: Double) -> Double {
        guard snapshot.status == .ongoing else {
            return 0
        }
        let proximity = clampedUnit(Foundation.exp(-distanceKm / 2.4))
        return 0.18 + 0.22 * proximity
    }

    private func nearbyImminentUpcomingBoost(
        snapshot: EventStatusSnapshot,
        distanceKm: Double,
        now: Date
    ) -> Double {
        guard snapshot.status == .upcoming,
              let startDate = snapshot.startDate else {
            return 0
        }

        let deltaHours = max(startDate.timeIntervalSince(now), 0) / 3_600
        guard deltaHours <= 2 else {
            return 0
        }
        let imminence = 1 - (deltaHours / 2)
        let proximity = clampedUnit(Foundation.exp(-distanceKm / 3.0))
        return 0.04 * imminence * proximity
    }

    private func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func bootstrapNearbyPlacesIfNeeded() {
        if shouldBootstrapFromBundled {
            reloadNearbyPlacesAroundCurrentLocation(userInitiated: false)
            return
        }

        if places.isEmpty {
            scheduleDeferredLoadAllPlaces(center: resolvedCenter)
        } else {
            loadAllPlacesIfNeeded(center: resolvedCenter)
        }
        if let region = mapCameraPosition.region {
            scheduleViewportReload(for: region, reason: "viewAppear", debounceNanoseconds: 0)
        }
    }

    private func scheduleDeferredLoadAllPlaces(center: CLLocationCoordinate2D) {
        guard !didLoadAllPlaces, !isLoadingAllPlaces else {
            return
        }
        deferredLoadAllTask?.cancel()
        deferredLoadAllTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.deferredLoadAllDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.loadAllPlacesIfNeeded(center: center)
            }
        }
    }

    private func reloadNearbyPlacesAroundCurrentLocation(userInitiated: Bool) {
        if !userInitiated, bootstrapTask != nil {
            return
        }

        bootstrapTask?.cancel()
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            let bootstrapStartRevision = self.cameraChangeRevision
            let bootstrapStartRegion = self.normalizedRegion(self.lastKnownMapRegion ?? self.mapCameraPosition.region)

            let locationResolution = await self.locationProvider.resolveCurrentLocation(
                fallback: self.initialCenter
            )

            guard !Task.isCancelled else {
                return
            }

            self.bootstrapTask = nil
            if let fallbackReason = locationResolution.fallbackReason {
                self.presentLocationFallbackNoticeIfNeeded(for: fallbackReason)
            }
            let center = locationResolution.coordinate
            let previousCenter = self.resolvedCenter
            self.resolvedCenter = center
            if self.distanceKm(from: previousCenter, to: center) >= 0.02 {
                self.invalidateAllPlacesDerivedCaches()
            }

            let targetRegion = MKCoordinateRegion(
                center: center,
                span: self.defaultMapSpan
            )
            if userInitiated {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.setProgrammaticMapPosition(
                        .region(targetRegion),
                        source: "resetLocationResolved",
                        suppressionWindow: 0.35
                    )
                }
            }

            let currentViewportRegion = self.normalizedRegion(self.lastKnownMapRegion ?? self.mapCameraPosition.region)
            let didUserMoveViewportSinceBootstrap: Bool = {
                guard !userInitiated else { return false }
                if self.cameraChangeRevision != bootstrapStartRevision {
                    return true
                }
                guard let bootstrapStartRegion,
                      let currentViewportRegion else {
                    return false
                }
                return self.shouldTriggerViewportReload(
                    from: bootstrapStartRegion,
                    to: currentViewportRegion
                )
            }()
            let effectiveReloadRegion: MKCoordinateRegion = didUserMoveViewportSinceBootstrap
                ? (currentViewportRegion ?? targetRegion)
                : targetRegion

            self.scheduleDeferredLoadAllPlaces(center: center)
            self.scheduleViewportReload(
                for: effectiveReloadRegion,
                reason: userInitiated ? "resetLocation" : "bootstrap",
                debounceNanoseconds: userInitiated ? 0 : 30_000_000
            )
            self.shouldBootstrapFromBundled = false
        }
    }

    private func presentLocationFallbackNoticeIfNeeded(for reason: AppLocationFallbackReason) {
        guard shownLocationFallbackReasons.contains(reason) == false else {
            return
        }
        shownLocationFallbackReasons.insert(reason)
        locationFallbackNotice = LocationFallbackNotice(reason: reason)
    }

    private func presentTopNotice(message: String) {
        topNoticeDismissTask?.cancel()
        topNoticeDismissTask = nil
        topNotice = TopNotice(message: message)
        let dismissDelay = checkInBlockedNoticeDurationNanoseconds
        topNoticeDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: dismissDelay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            self.topNotice = nil
            self.topNoticeDismissTask = nil
        }
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print("[HomeMapViewModel] \(message)")
#endif
        logger.info("\(message, privacy: .public)")
    }

    private func normalizedPlaces(_ loaded: [HePlace], fallbackToMockWhenEmpty: Bool) -> [HePlace] {
        let source = (fallbackToMockWhenEmpty && loaded.isEmpty) ? MockHePlaceRepository.load() : loaded
        return source.filter { $0.heType != .nature }
    }

    private func replaceAllPlaces(_ newPlaces: [HePlace]) {
        places = newPlaces
        allPlacesRevision &+= 1
        invalidateAllPlacesDerivedCaches()
        prewarmSideDrawerSnapshotForLaunch()
        prewarmCalendarCacheForLaunch()
    }

    private func replaceRenderedPlaces(_ newPlaces: [HePlace]) {
        if sameRenderedPlaceIDs(lhs: renderedPlaces, rhs: newPlaces) {
            return
        }
        renderedPlaces = newPlaces
        placesRevision &+= 1
        markerEntriesCacheKey = nil
        markerEntriesCache = []
        markerEntriesIndexByID = [:]
        reconcileSelectionForMapFilter()
    }

    private func replaceNearbyRecommendationPlaces(_ newPlaces: [HePlace]) {
        let limited = Array(newPlaces.prefix(maxNearbyRecommendationPlaces))
        if sameRenderedPlaceIDs(lhs: nearbyRecommendationPlaces, rhs: limited) {
            return
        }
        nearbyRecommendationPlaces = limited
        nearbyRecommendationRevision &+= 1
        invalidateNearbyRankingCache()
    }

    private func sameRenderedPlaceIDs(lhs: [HePlace], rhs: [HePlace]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        return zip(lhs, rhs).allSatisfy { $0.id == $1.id }
    }

    private func loadAllPlacesIfNeeded(center: CLLocationCoordinate2D) {
        guard !didLoadAllPlaces, !isLoadingAllPlaces else {
            return
        }

        isLoadingAllPlaces = true
        loadAllTask?.cancel()
        loadAllTask = Task { [weak self] in
            guard let self else { return }
            let loadedAllTask = Task.detached(priority: .utility) {
                EncodedHePlaceRepository.loadAll(center: center)
            }
            let loadedAll = await withTaskCancellationHandler(operation: {
                await loadedAllTask.value
            }, onCancel: {
                loadedAllTask.cancel()
            })

            guard !Task.isCancelled else {
                return
            }

            self.isLoadingAllPlaces = false
            let normalized = self.normalizedPlaces(loadedAll, fallbackToMockWhenEmpty: false)
            if normalized.isEmpty {
                self.debugLog("loadAll done center=(\(center.latitude),\(center.longitude)) loaded=0, keep existing allPlaces=\(self.places.count)")
                return
            }

            self.replaceAllPlaces(normalized)
            self.didLoadAllPlaces = true
            self.debugLog("loadAll done center=(\(center.latitude),\(center.longitude)) loaded=\(loadedAll.count) normalized=\(normalized.count)")
        }
    }

    func handleMapCameraChange(_ region: MKCoordinateRegion) {
        guard let normalizedRegion = normalizedRegion(region) else {
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastCameraMotionAt) < cameraMotionQuietWindow {
            pendingSettledCameraRegion = normalizedRegion
            scheduleDeferredCameraEndHandling()
            return
        }
        deferredCameraEndTask?.cancel()
        deferredCameraEndTask = nil
        pendingSettledCameraRegion = nil
        processSettledMapCameraChange(normalizedRegion)
    }

    private func processSettledMapCameraChange(_ normalizedRegion: MKCoordinateRegion) {

        if shouldSuppressCameraMoveSideEffects(for: normalizedRegion) {
            return
        }
        let previousRegion = lastKnownMapRegion
        lastKnownMapRegion = normalizedRegion
        guard shouldTriggerViewportReload(from: previousRegion, to: normalizedRegion) else {
            return
        }

        cameraMoveCountSinceHardRecycle += 1

        let movedSinceRecycle = distanceKm(
            from: lastMapRecycleCenter ?? normalizedRegion.center,
            to: normalizedRegion.center
        )
        if movedSinceRecycle >= minMoveForIdleRecycleKm {
            hasSignificantMoveSinceLastRecycle = true
        }
        let zoomRatioSinceRecycle = zoomScaleRatio(
            from: lastMapRecycleSpan ?? normalizedRegion.span,
            to: normalizedRegion.span
        )
        if zoomRatioSinceRecycle >= minZoomRatioForIdleRecycle {
            hasSignificantMoveSinceLastRecycle = true
        }

        cameraChangeRevision &+= 1
        scheduleIdleRecycleIfNeeded(revision: cameraChangeRevision)
        scheduleViewportReload(for: normalizedRegion, reason: "cameraMove", debounceNanoseconds: 420_000_000)
    }

    private func scheduleDeferredCameraEndHandling() {
        deferredCameraEndTask?.cancel()
        deferredCameraEndTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.cameraEndDebounceNanoseconds)
            guard !Task.isCancelled,
                  let pendingRegion = self.pendingSettledCameraRegion else {
                return
            }
            self.pendingSettledCameraRegion = nil
            self.handleMapCameraChange(pendingRegion)
        }
    }

    func handleMapCameraMotion(_ _: MKCoordinateRegion) {
        let now = Date()
        // Keep continuous callback lightweight; avoid mutating region state per-frame.
        if now.timeIntervalSince(lastCameraMotionHeartbeatAt) < 0.12 {
            return
        }
        lastCameraMotionHeartbeatAt = now
        lastCameraMotionAt = now
    }

    private func shouldTriggerViewportReload(
        from previousRegion: MKCoordinateRegion?,
        to currentRegion: MKCoordinateRegion
    ) -> Bool {
        guard let previousRegion else {
            return true
        }
        let movedKm = distanceKm(from: previousRegion.center, to: currentRegion.center)
        if movedKm >= minCameraMoveForViewportReloadKm {
            return true
        }
        let zoomRatio = zoomScaleRatio(from: previousRegion.span, to: currentRegion.span)
        return zoomRatio >= minCameraZoomRatioForViewportReload
    }

    private func registerProgrammaticCameraChangeTarget(
        _ region: MKCoordinateRegion,
        source: String,
        suppressionWindow: TimeInterval? = nil
    ) {
        pendingProgrammaticCameraTargetRegion = region
        pendingProgrammaticCameraSource = source
        pendingProgrammaticCameraExpiresAt = Date().addingTimeInterval(
            suppressionWindow ?? programmaticCameraSuppressionWindow
        )
    }

    private func clearProgrammaticCameraChangeTarget() {
        pendingProgrammaticCameraTargetRegion = nil
        pendingProgrammaticCameraSource = nil
        pendingProgrammaticCameraExpiresAt = .distantPast
    }

    private func shouldSuppressCameraMoveSideEffects(for region: MKCoordinateRegion) -> Bool {
        let now = Date()
        guard now <= pendingProgrammaticCameraExpiresAt,
              let target = pendingProgrammaticCameraTargetRegion else {
            if now > pendingProgrammaticCameraExpiresAt {
                clearProgrammaticCameraChangeTarget()
            }
            return false
        }

        let centerDistanceKm = distanceKm(from: target.center, to: region.center)
        let latSpanDiff = abs(target.span.latitudeDelta - region.span.latitudeDelta)
        let lngSpanDiff = abs(target.span.longitudeDelta - region.span.longitudeDelta)
        let source = pendingProgrammaticCameraSource ?? "programmatic"
        let shouldBlockStaleProgrammaticUpdate = shouldBlockStaleProgrammaticCameraChange(for: source)
        let isTargetMatch = centerDistanceKm <= programmaticCameraCenterToleranceKm &&
            latSpanDiff <= programmaticCameraSpanTolerance &&
            lngSpanDiff <= programmaticCameraSpanTolerance
        guard isTargetMatch else {
            guard shouldBlockStaleProgrammaticUpdate else {
                return false
            }
            debugLog(
                "skipViewportReload reason=staleProgrammaticCameraChange source=\(source) centerDistanceKm=\(centerDistanceKm)"
            )
            return true
        }

        debugLog(
            "skipViewportReload reason=programmaticCameraChange source=\(source) centerDistanceKm=\(centerDistanceKm)"
        )
        if !shouldBlockStaleProgrammaticUpdate {
            clearProgrammaticCameraChangeTarget()
        }
        return true
    }

    private func maybeHardRecycleMapForCameraMove(region: MKCoordinateRegion) {
        let baseline = lastHardRecycleCenter ?? region.center
        let movedKm = distanceKm(from: baseline, to: region.center)
        let reachedDistanceTrigger = movedKm >= cameraHardRecycleDistanceKm
        let reachedCountTrigger = cameraMoveCountSinceHardRecycle >= cameraHardRecycleEveryMoves
        guard reachedDistanceTrigger || reachedCountTrigger else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHardRecycleAt) >= cameraHardRecycleCooldown else {
            return
        }
        let reason: String
        if reachedDistanceTrigger {
            reason = "cameraMoveHardRecycleDistance:\(Int(movedKm.rounded()))km"
        } else {
            reason = "cameraMoveHardRecycleCount:\(cameraMoveCountSinceHardRecycle)"
        }
        forceMapViewRebuild(
            reason: reason,
            pinnedRegion: region
        )
    }

    private func maybeHardRecycleMapForMemoryPressure(region: MKCoordinateRegion, trigger: String) {
        guard let currentMemoryMB = currentAppMemoryUsageMB(),
              currentMemoryMB >= memoryHardRecycleThresholdMB else {
            return
        }
        if currentMemoryMB >= memoryEmergencyThresholdMB {
            forceEmergencyMemoryRecovery(region: region, currentMemoryMB: currentMemoryMB, trigger: trigger)
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastHardRecycleAt) >= cameraHardRecycleCooldown else {
            return
        }
        forceMapViewRebuild(
            reason: "\(trigger)MemoryHigh:\(Int(currentMemoryMB.rounded()))MB",
            pinnedRegion: region
        )
    }

    private func startPeriodicHardRecycleTask() {
        periodicHardRecycleTask?.cancel()
        periodicHardRecycleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: periodicHardRecycleIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                self.handlePeriodicHardRecycleTick()
            }
        }
    }

    private func startMemoryWatchdogTask() {
        memoryWatchdogTask?.cancel()
        memoryWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: memoryWatchdogIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                guard let region = self.lastKnownMapRegion else { continue }
                guard !self.hasActiveMapInteractionState else { continue }
                self.maybeHardRecycleMapForMemoryPressure(region: region, trigger: "watchdog")
            }
        }
    }

    private func handlePeriodicHardRecycleTick() {
        guard let region = lastKnownMapRegion else {
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastCameraMotionAt) < periodicHardRecycleMotionQuietWindow {
            debugLog("skipPeriodicHardRecycle reason=cameraMotionActive")
            return
        }
        guard !hasActiveMapInteractionState else {
            debugLog("skipPeriodicHardRecycle reason=activeInteraction")
            return
        }
        maybeHardRecycleMapForMemoryPressure(region: region, trigger: "periodicTick")
        guard now.timeIntervalSince(lastHardRecycleAt) >= periodicHardRecycleInterval else {
            return
        }
        forceMapViewRebuild(reason: "periodicTick", pinnedRegion: region)
    }

    private var hasActiveMapInteractionState: Bool {
        _selectedPlaceID != nil ||
        _markerActionPlaceID != nil ||
        _quickCardPlaceID != nil ||
        _expiredCardPlaceID != nil ||
        _temporaryExpiredMarkerPlaceID != nil ||
        _detailPlaceID != nil ||
        isSideDrawerOpen ||
        isFavoriteDrawerOpen ||
        isCalendarPresented
    }

    private func forceEmergencyMemoryRecovery(
        region: MKCoordinateRegion,
        currentMemoryMB: Double,
        trigger: String
    ) {
        let emergencyRegion = expandedMapRegion(region, scale: 1.05)
        let inEmergencyRegion = filteredPlacesInRegion(renderedPlaces, region: emergencyRegion)
        let emergencyCandidates = nearestPlacesByDistance(inEmergencyRegion, limit: memoryEmergencyRenderedLimit)
        // Keep active places (selected/quick/detail/menu) even when emergency trimming aggressively.
        let emergencyPlaces = ensureActivePlacesIncluded(
            in: emergencyCandidates,
            sourcePool: renderedPlaces,
            limit: memoryEmergencyRenderedLimit
        )
        replaceRenderedPlaces(emergencyPlaces)
        invalidateAllPlacesDerivedCaches()
        forceMapViewRebuild(
            reason: "\(trigger)MemoryEmergency:\(Int(currentMemoryMB.rounded()))MB",
            pinnedRegion: region
        )
    }

    private func scheduleIdleRecycleIfNeeded(revision: UInt64) {
        idleRecycleTask?.cancel()
        idleRecycleTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: idleViewportTrimDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard revision == self.cameraChangeRevision else { return }
            guard self.hasSignificantMoveSinceLastRecycle else { return }

            let now = Date()
            guard now.timeIntervalSince(self.lastIdleTrimAt) >= self.idleTrimCooldown else { return }
            self.performIdleSoftTrim()
        }
    }

    private func performIdleSoftTrim() {
        guard let region = lastKnownMapRegion else {
            return
        }
        let trimRegion = expandedMapRegion(region, scale: idleTrimScale)
        let trimmed = filteredPlacesInRegion(renderedPlaces, region: trimRegion)
        let limited = ensureActivePlacesIncluded(
            in: Array(trimmed.prefix(maxRenderedPlaces)),
            sourcePool: renderedPlaces,
            limit: maxRenderedPlaces
        )
        replaceRenderedPlaces(limited)
        hasSignificantMoveSinceLastRecycle = false
        lastIdleTrimAt = Date()
        lastMapRecycleCenter = region.center
        lastMapRecycleSpan = region.span
        debugLog("idleSoftTrim regionCenter=(\(region.center.latitude),\(region.center.longitude)) kept=\(limited.count)")
    }

    private func scheduleViewportReload(
        for region: MKCoordinateRegion,
        reason: String,
        debounceNanoseconds: UInt64
    ) {
        let signature = ViewportQuerySignature(region: region, filter: mapCategoryFilter)
        if signature == lastViewportQuerySignature, reason != "bootstrap" {
            return
        }
        if reason == "cameraMove",
           let lastLoadedExpandedRegion {
            let expanded = expandedMapRegion(region, scale: mapBufferScale)
            if isRegion(expanded, containedIn: lastLoadedExpandedRegion) {
                lastViewportQuerySignature = signature
                trimRenderedPlacesForEnvelope(expanded, reason: "cameraMoveContained")
                debugLog(
                    "skipViewportReload reason=\(reason) center=(\(region.center.latitude),\(region.center.longitude)) withinLoadedEnvelope=true"
                )
                return
            }
        }

        viewportReloadTask?.cancel()
        viewportReloadTask = Task { [weak self] in
            guard let self else { return }
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self.reloadRenderedPlaces(for: region, signature: signature, reason: reason)
        }
    }

    private func reloadRenderedPlaces(
        for region: MKCoordinateRegion,
        signature: ViewportQuerySignature,
        reason: String
    ) async {
        let expandedRegion = expandedMapRegion(region, scale: mapBufferScale)
        let rawQueryRadiusKm = max(minimumViewportRadiusKm, diagonalRadiusKm(for: expandedRegion))
        let queryRadiusKm = min(rawQueryRadiusKm, 80)
        let dynamicQueryLimit = Int((queryRadiusKm * 50).rounded(.up))
        let queryLimit = min(1_500, max(nearbyLimit, max(200, dynamicQueryLimit)))
        let userCenter = resolvedCenter

        let sourcePlaces: [HePlace]
        let sourceMode: String
        let loadedCount: Int
        let effectiveNow = Date()

        if didLoadAllPlaces, !places.isEmpty {
            sourcePlaces = interactivePlaces(
                from: places,
                now: effectiveNow
            )
            sourceMode = "inMemoryAllCached"
            loadedCount = sourcePlaces.count
        } else if isLoadingAllPlaces, !places.isEmpty {
            sourcePlaces = interactivePlaces(from: places, now: effectiveNow)
            sourceMode = "inMemorySeed"
            loadedCount = places.count
        } else {
            let searchCenter = expandedRegion.center
            nearbyLoadTask?.cancel()
            let queryToken = UUID()
            activeNearbyQueryToken = queryToken
            let nearbyLoadTask = Task.detached(priority: .userInitiated) {
                EncodedHePlaceRepository.loadNearby(
                    center: searchCenter,
                    radiusKm: queryRadiusKm,
                    limit: queryLimit
                )
            }
            self.nearbyLoadTask = nearbyLoadTask
            let loaded = await withTaskCancellationHandler(operation: {
                await nearbyLoadTask.value
            }, onCancel: {
                nearbyLoadTask.cancel()
            })

            guard !Task.isCancelled else {
                return
            }
            guard self.activeNearbyQueryToken == queryToken else {
                return
            }
            self.nearbyLoadTask = nil
            self.activeNearbyQueryToken = nil

            let normalized = normalizedPlaces(loaded, fallbackToMockWhenEmpty: reason == "bootstrap")
            sourcePlaces = interactivePlaces(
                from: rebasedPlaces(normalized, center: userCenter),
                now: effectiveNow
            )
            sourceMode = "bundledNearby"
            loadedCount = loaded.count
        }

        lastViewportQuerySignature = signature
        lastLoadedExpandedRegion = expandedRegion
        scheduleNearbyPreheatIfNeeded(
            center: expandedRegion.center,
            radiusKm: queryRadiusKm,
            limit: queryLimit,
            sourceMode: sourceMode
        )
        let recommendationRegion = expandedMapRegion(region, scale: nearbyRecommendationBufferScale)
        let activeIDs = activePlaceIDsSnapshot()
        let renderedLimit = maxRenderedPlaces
        let recommendationLimit = maxNearbyRecommendationPlaces
        let clusterThreshold = suspectCoordinateClusterThreshold

        let rankingTask = Task.detached(priority: .userInitiated) {
            let inRegion = HomeMapSpatialCompute.filteredPlacesInRegion(sourcePlaces, region: expandedRegion)
            let nearestByViewportCenter = HomeMapSpatialCompute.nearestPlacesByDistance(
                inRegion,
                limit: renderedLimit,
                reference: expandedRegion.center
            )
            let renderedClusterResult = HomeMapSpatialCompute.filterSuspectCoordinateClusters(
                nearestByViewportCenter,
                threshold: clusterThreshold,
                activeIDs: activeIDs
            )
            let rendered = HomeMapSpatialCompute.ensureActivePlacesIncluded(
                in: renderedClusterResult.places,
                sourcePool: inRegion,
                activeIDs: activeIDs,
                limit: renderedLimit,
                reference: expandedRegion.center
            )

            let recommendationInRegion = HomeMapSpatialCompute.filteredPlacesInRegion(
                sourcePlaces,
                region: recommendationRegion
            )
            let recommendationNearest = HomeMapSpatialCompute.nearestPlacesByDistance(
                recommendationInRegion,
                limit: recommendationLimit,
                reference: recommendationRegion.center
            )
            let recommendationClusterResult = HomeMapSpatialCompute.filterSuspectCoordinateClusters(
                recommendationNearest,
                threshold: clusterThreshold,
                activeIDs: activeIDs
            )
            let recommendation = HomeMapSpatialCompute.ensureActivePlacesIncluded(
                in: recommendationClusterResult.places,
                sourcePool: recommendationInRegion,
                activeIDs: activeIDs,
                limit: recommendationLimit,
                reference: recommendationRegion.center
            )

            return ViewportRankingPayload(
                rendered: rendered,
                recommendation: recommendation,
                inRegionCount: inRegion.count,
                recommendationInRegionCount: recommendationInRegion.count,
                renderedDroppedCount: renderedClusterResult.dropped,
                recommendationDroppedCount: recommendationClusterResult.dropped
            )
        }
        let ranking = await withTaskCancellationHandler(operation: {
            await rankingTask.value
        }, onCancel: {
            rankingTask.cancel()
        })
        guard !Task.isCancelled else {
            return
        }

        let rebasedRendered = rebasedPlaces(ranking.rendered, center: userCenter)
        debugLog(
            "reloadRendered reason=\(reason) source=\(sourceMode) center=(\(region.center.latitude),\(region.center.longitude)) span=(\(region.span.latitudeDelta),\(region.span.longitudeDelta)) rawQueryRadiusKm=\(rawQueryRadiusKm) queryRadiusKm=\(queryRadiusKm) queryLimit=\(queryLimit) loaded=\(loadedCount) sourcePlaces=\(sourcePlaces.count) inRegion=\(ranking.inRegionCount) rendered=\(ranking.rendered.count) droppedRendered=\(ranking.renderedDroppedCount) recRegion=\(ranking.recommendationInRegionCount) droppedRec=\(ranking.recommendationDroppedCount)"
        )

        let rebasedRecommendationPlaces = rebasedPlaces(ranking.recommendation, center: userCenter)
        replaceNearbyRecommendationPlaces(rebasedRecommendationPlaces)

        replaceRenderedPlaces(rebasedRendered)
        if places.isEmpty, !rebasedRendered.isEmpty {
            replaceAllPlaces(rebasedRendered)
        }
        if nearbyNotificationEnabled, reason != "cameraMove", reason != "cameraMoveContained" {
            scheduleNearbyReminderSync()
        }
        maybeApplyInitialRecommendationFocus(triggerReason: reason, now: effectiveNow)
        if !ranking.rendered.isEmpty {
            scheduleAutoOpenIfNeeded()
        }
    }

    private func maybeApplyInitialRecommendationFocus(triggerReason: String, now: Date) {
        guard !hasAppliedInitialRecommendationFocus else {
            return
        }
        guard triggerReason == "bootstrap" || triggerReason == "viewAppear" else {
            return
        }

        if let focusRevision = initialRecommendationFocusRevision,
           cameraChangeRevision != focusRevision {
            hasAppliedInitialRecommendationFocus = true
            debugLog("skipInitialRecommendationFocus reason=userCameraChanged")
            return
        }

        guard let target = recommendedPlace(now: now) else {
            return
        }
        hasAppliedInitialRecommendationFocus = true
        debugLog("applyInitialRecommendationFocus place=\(target.name)")
        withAnimation(.easeInOut(duration: 0.24)) {
            setProgrammaticMapPosition(
                .region(nonExpandingFocusedRegion(for: target)),
                source: "initialRecommendationFocus",
                suppressionWindow: 0.35
            )
        }
    }

    private func scheduleNearbyPreheatIfNeeded(
        center: CLLocationCoordinate2D,
        radiusKm: Double,
        limit: Int,
        sourceMode: String
    ) {
        guard sourceMode == "bundledNearby", !didLoadAllPlaces else {
            return
        }
        let signature = NearbyPreheatSignature(center: center, radiusKm: radiusKm)
        guard signature != lastNearbyPreheatSignature else {
            return
        }
        lastNearbyPreheatSignature = signature

        nearbyPreheatTask?.cancel()
        nearbyPreheatTask = Task.detached(priority: .utility) {
            if Task.isCancelled {
                return
            }
            EncodedHePlaceRepository.preheatNeighborhood(
                center: center,
                radiusKm: radiusKm,
                limit: limit
            )
        }
    }

    private func trimRenderedPlacesForEnvelope(_ envelope: MKCoordinateRegion, reason: String) {
        let inEnvelope = filteredPlacesInRegion(renderedPlaces, region: envelope)
        let limited = ensureActivePlacesIncluded(
            in: nearestPlacesByDistance(
                inEnvelope,
                limit: maxRenderedPlaces,
                reference: envelope.center
            ),
            sourcePool: renderedPlaces,
            limit: maxRenderedPlaces,
            reference: envelope.center
        )
        if sameRenderedPlaceIDs(lhs: renderedPlaces, rhs: limited) {
            return
        }
        replaceRenderedPlaces(limited)
        debugLog("trimRenderedPlaces reason=\(reason) inEnvelope=\(inEnvelope.count) kept=\(limited.count)")
    }

    private func nearestPlacesByDistance(
        _ source: [HePlace],
        limit: Int,
        reference: CLLocationCoordinate2D? = nil
    ) -> [HePlace] {
        let referenceCoordinate = reference ?? resolvedCenter
        return HomeMapSpatialCompute.nearestPlacesByDistance(
            source,
            limit: limit,
            reference: referenceCoordinate
        )
    }

    private func ensureActivePlacesIncluded(
        in candidates: [HePlace],
        sourcePool: [HePlace],
        limit: Int,
        reference: CLLocationCoordinate2D? = nil
    ) -> [HePlace] {
        let referenceCoordinate = reference ?? resolvedCenter
        return HomeMapSpatialCompute.ensureActivePlacesIncluded(
            in: candidates,
            sourcePool: sourcePool,
            activeIDs: activePlaceIDsSnapshot(),
            limit: limit,
            reference: referenceCoordinate
        )
    }

    private func activePlaceIDsSnapshot() -> Set<UUID> {
        Set([
            _detailPlaceID,
            _quickCardPlaceID,
            _expiredCardPlaceID,
            _selectedPlaceID,
            _markerActionPlaceID,
            _temporaryExpiredMarkerPlaceID
        ].compactMap { $0 })
    }

    private func rebasedPlaces(_ source: [HePlace], center: CLLocationCoordinate2D) -> [HePlace] {
        guard !source.isEmpty else {
            return []
        }

        var rebased: [HePlace] = []
        rebased.reserveCapacity(source.count)
        for place in source {
            let distance = distanceMeters(from: center, to: place.coordinate)
            if abs(distance - place.distanceMeters) < 0.5 {
                rebased.append(place)
                continue
            }
            rebased.append(
                HePlace(
                    id: place.id,
                    name: place.name,
                    heType: place.heType,
                    coordinate: place.coordinate,
                    geoSource: place.geoSource,
                    startAt: place.startAt,
                    endAt: place.endAt,
                    distanceMeters: distance,
                    scaleScore: place.scaleScore,
                    hint: place.hint,
                    openHours: place.openHours,
                    mapSpot: place.mapSpot,
                    detailDescription: place.detailDescription,
                    oneLiner: place.oneLiner,
                    detailDescriptionZH: place.detailDescriptionZH,
                    oneLinerZH: place.oneLinerZH,
                    detailDescriptionEN: place.detailDescriptionEN,
                    oneLinerEN: place.oneLinerEN,
                    sourceURLs: place.sourceURLs,
                    descriptionSourceURL: place.descriptionSourceURL,
                    imageSourceURL: place.imageSourceURL,
                    imageRef: place.imageRef,
                    imageTag: place.imageTag,
                    imageHint: place.imageHint,
                    heatScore: place.heatScore,
                    surpriseScore: place.surpriseScore
                )
            )
        }
        return rebased
    }

    private func nearbyRecommendationSourcePlaces() -> [HePlace] {
        let source = nearbyRecommendationPlaces
        guard mapCategoryFilter != .all else {
            return source
        }
        return source.filter { $0.heType.rawValue == mapCategoryFilter.rawValue }
    }

    private func interactivePlaces(from source: [HePlace], now: Date) -> [HePlace] {
        source.filter { isPlaceInteractionEnabled($0, now: now) }
    }

    private func markerClusters(from source: [HePlace], region: MKCoordinateRegion) -> [MarkerClusterSummary] {
        guard !source.isEmpty else {
            return []
        }
        if source.count == 1, let only = source.first {
            return [MarkerClusterSummary(anchor: only, memberIDs: [only.id])]
        }

        let now = Date()
        let thresholdMeters = markerCollisionThresholdMeters(for: region)
        let sorted = source.sorted { isEarlierForClusterAnchor($0, $1, now: now) }
        let count = sorted.count
        var parent = Array(0..<count)

        func find(_ index: Int) -> Int {
            var node = index
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }

        func union(_ lhs: Int, _ rhs: Int) {
            let leftRoot = find(lhs)
            let rightRoot = find(rhs)
            guard leftRoot != rightRoot else { return }
            parent[rightRoot] = leftRoot
        }

        for left in 0..<count {
            let lhs = sorted[left]
            for right in (left + 1)..<count {
                let rhs = sorted[right]
                let distance = distanceMeters(from: lhs.coordinate, to: rhs.coordinate)
                if distance <= thresholdMeters {
                    union(left, right)
                }
            }
        }

        var groups: [Int: [HePlace]] = [:]
        groups.reserveCapacity(count)
        for index in 0..<count {
            groups[find(index), default: []].append(sorted[index])
        }

        let summaries = groups.values.compactMap { group -> MarkerClusterSummary? in
            guard !group.isEmpty else { return nil }
            let ordered = group.sorted { isEarlierForClusterAnchor($0, $1, now: now) }
            guard let defaultAnchor = ordered.first else { return nil }
            let memberIDs = ordered.map(\.id)
            return MarkerClusterSummary(anchor: defaultAnchor, memberIDs: memberIDs)
        }
        .sorted { isCloserAndEarlier($0.anchor, $1.anchor) }

        return summaries
    }

    private func markerCollisionThresholdMeters(for region: MKCoordinateRegion) -> Double {
        let screenBounds = activeScreenBounds()
        let widthPoints = max(screenBounds.width, 320)
        let heightPoints = max(screenBounds.height, 568)
        let latMeters = max(region.span.latitudeDelta, 0.001) * 111_320
        let lngScale = max(cos(region.center.latitude * .pi / 180), 0.1)
        let lngMeters = max(region.span.longitudeDelta, 0.001) * 111_320 * lngScale
        let metersPerPointLat = latMeters / heightPoints
        let metersPerPointLng = lngMeters / widthPoints
        let metersPerPoint = max((metersPerPointLat + metersPerPointLng) / 2, 0.2)
        return max(minMarkerCollisionMeters, metersPerPoint * markerCollisionPointThreshold)
    }

    private func activeScreenBounds() -> CGRect {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = windowScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            return keyWindow.screen.bounds
        }
        if let firstWindow = windowScenes.flatMap(\.windows).first {
            return firstWindow.screen.bounds
        }
        if let firstScene = windowScenes.first {
            return firstScene.screen.bounds
        }
        // Fallback size when scene/window is not available yet.
        return CGRect(x: 0, y: 0, width: 390, height: 844)
    }

    private func isOverlapClusterPlace(_ place: HePlace, region: MKCoordinateRegion) -> Bool {
        let clusters = markerClusters(from: mapPlaces(), region: region)
        guard let cluster = clusters.first(where: { $0.memberIDs.contains(place.id) }) else {
            return false
        }
        return cluster.count > 1
    }

    private func isPlaceInteractionEnabled(_ place: HePlace, now: Date = Date()) -> Bool {
        !isPlaceArchivedAfterRetention(place, now: now)
    }

    private func isPlaceArchivedAfterRetention(_ place: HePlace, now: Date) -> Bool {
        let snapshot = EventStatusResolver.snapshot(
            startAt: place.startAt,
            endAt: place.endAt,
            now: now
        )
        guard snapshot.status == .ended else {
            return false
        }
        guard let anchorDate = snapshot.endDate ?? snapshot.startDate else {
            return false
        }
        guard let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -interactionRetentionDaysAfterEnded,
            to: now
        ) else {
            return false
        }
        return anchorDate < cutoffDate
    }

    private func expandedMapRegion(_ region: MKCoordinateRegion, scale: Double) -> MKCoordinateRegion {
        let clampedScale = max(1, scale)
        return MKCoordinateRegion(
            center: region.center,
            span: MKCoordinateSpan(
                latitudeDelta: max(region.span.latitudeDelta * clampedScale, 0.005),
                longitudeDelta: max(region.span.longitudeDelta * clampedScale, 0.005)
            )
        )
    }

    private func diagonalRadiusKm(for region: MKCoordinateRegion) -> Double {
        let halfLatMeters = max(region.span.latitudeDelta, 0.001) * 111_320 / 2
        let lngScale = max(cos(region.center.latitude * .pi / 180), 0.1)
        let halfLngMeters = max(region.span.longitudeDelta, 0.001) * 111_320 * lngScale / 2
        let halfDiagonalMeters = sqrt(halfLatMeters * halfLatMeters + halfLngMeters * halfLngMeters)
        return max(halfDiagonalMeters / 1_000, 1)
    }

    private func filteredPlacesInRegion(_ source: [HePlace], region: MKCoordinateRegion) -> [HePlace] {
        HomeMapSpatialCompute.filteredPlacesInRegion(source, region: region)
    }

    private func isRegion(_ region: MKCoordinateRegion, containedIn envelope: MKCoordinateRegion) -> Bool {
        let regionHalfLat = region.span.latitudeDelta / 2
        let regionHalfLng = region.span.longitudeDelta / 2
        let envelopeHalfLat = envelope.span.latitudeDelta / 2
        let envelopeHalfLng = envelope.span.longitudeDelta / 2

        return abs(region.center.latitude - envelope.center.latitude) + regionHalfLat <= envelopeHalfLat &&
            abs(region.center.longitude - envelope.center.longitude) + regionHalfLng <= envelopeHalfLng
    }

    private func distanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lon1 = lhs.longitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let lon2 = rhs.longitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(1 - a, 0)))
        return earthRadiusMeters * c
    }

    private func invalidateAllPlacesDerivedCaches() {
        invalidateNearbyRankingCache()
        invalidateSideDrawerSnapshotCache()
        invalidateCalendarDetailSnapshotCache()
    }

    private func invalidateNearbyRankingCache() {
        nearbyRankingCacheKey = nil
        nearbyRankingCache = []
    }

    private func calendarDetailSnapshot(now: Date = Date()) -> [HePlace] {
        let usesRenderedSource = places.isEmpty
        let sourceRevision = usesRenderedSource ? placesRevision : allPlacesRevision
        let dayStart = Calendar.current.startOfDay(for: now)
        let daySerial = Int(dayStart.timeIntervalSince1970 / 86_400)
        let cacheKey = CalendarDetailSnapshotCacheKey(
            sourceRevision: sourceRevision,
            usesRenderedSource: usesRenderedSource,
            daySerial: daySerial
        )

        if calendarDetailSnapshotCacheKey == cacheKey {
            return calendarDetailSnapshotCache
        }

        let source = usesRenderedSource ? renderedPlaces : places
        let interactive = interactivePlaces(from: source, now: now)
        calendarDetailSnapshotCacheKey = cacheKey
        calendarDetailSnapshotCache = interactive
        return interactive
    }

    private func invalidateCalendarDetailSnapshotCache() {
        calendarDetailSnapshotCacheKey = nil
        calendarDetailSnapshotCache = []
    }

    private func prewarmCalendarCacheForLaunch() {
        let sourcePlaces = places
        let sourceDetailPlaces = calendarDetailPlaces
        let referenceNow = Date()
        let locale = selectedLanguageLocale
        DispatchQueue.global(qos: .userInitiated).async {
            CalendarPageView.prewarmCache(
                places: sourcePlaces,
                detailPlaces: sourceDetailPlaces,
                now: referenceNow,
                locale: locale
            )
        }
    }

    private func prewarmSideDrawerSnapshotForLaunch() {
        _ = sideDrawerSnapshot()
    }

    private func restoreMapZoomAfterSelectionIfNeeded(focusedPlaceID: UUID?) {
        guard let focusedPlaceID,
              let place = place(for: focusedPlaceID) else {
            return
        }
        let targetRegion = MKCoordinateRegion(
            center: focusedCenter(for: place),
            span: defaultMapSpan
        )
        let duration = mapZoomRestoreAnimationDuration(
            from: lastKnownMapRegion ?? mapCameraPosition.region,
            to: targetRegion
        )
        withAnimation(.easeInOut(duration: duration)) {
            setProgrammaticMapPosition(.region(targetRegion))
        }
    }

    private func mapZoomRestoreAnimationDuration(
        from currentRegion: MKCoordinateRegion?,
        to targetRegion: MKCoordinateRegion
    ) -> TimeInterval {
        guard let currentRegion = normalizedRegion(currentRegion) else {
            return 0.25
        }

        let currentScale = max(
            currentRegion.span.latitudeDelta / max(defaultMapSpan.latitudeDelta, 0.000_001),
            currentRegion.span.longitudeDelta / max(defaultMapSpan.longitudeDelta, 0.000_001)
        )
        let targetScale = max(
            targetRegion.span.latitudeDelta / max(defaultMapSpan.latitudeDelta, 0.000_001),
            targetRegion.span.longitudeDelta / max(defaultMapSpan.longitudeDelta, 0.000_001)
        )
        let scaleRatio = max(currentScale / max(targetScale, 0.000_001), targetScale / max(currentScale, 0.000_001))

        if scaleRatio <= 1.2 {
            return 0.25
        }
        let normalized = min(max(log2(scaleRatio) / 4.0, 0), 1)
        return 0.25 + (normalized * 1.25)
    }

    private func scheduleMapZoomRestoreAfterQuickDismiss(focusedPlaceID: UUID?) {
        scheduleMapZoomRestoreAfterSelectionDismiss(focusedPlaceID: focusedPlaceID)
    }

    private func scheduleMapZoomRestoreAfterSelectionDismiss(focusedPlaceID: UUID?) {
        guard let focusedPlaceID else {
            return
        }
        mapZoomRestoreTask?.cancel()
        mapZoomRestoreTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            guard self._selectedPlaceID == nil,
                  self._markerActionPlaceID == nil,
                  self._quickCardPlaceID == nil,
                  self._expiredCardPlaceID == nil,
                  self._temporaryExpiredMarkerPlaceID == nil,
                  self._detailPlaceID == nil else {
                return
            }
            self.restoreMapZoomAfterSelectionIfNeeded(focusedPlaceID: focusedPlaceID)
            self.mapZoomRestoreTask = nil
        }
    }

    private func cancelPendingMapZoomRestore() {
        mapZoomRestoreTask?.cancel()
        mapZoomRestoreTask = nil
    }

    private func cancelPendingQuickCardPresentation() {
        quickCardPresentationTask?.cancel()
        quickCardPresentationTask = nil
    }

    private func cancelPendingMapFocus() {
        // Map focus is now synchronous; nothing to cancel.
    }

    func updateMapPositionFromInteraction(_ position: MapCameraPosition) {
        guard !isCalendarPresented,
              let incomingRegion = position.region,
              let normalizedIncomingRegion = normalizedRegion(incomingRegion) else {
            return
        }
        let now = Date()
        if shouldIgnoreTransientMapPositionAfterCalendarDismiss(normalizedIncomingRegion) {
            return
        }
        if shouldIgnoreStaleMapPositionDuringProgrammaticMove(normalizedIncomingRegion, now: now) {
            return
        }
        mapCameraPosition = .region(normalizedIncomingRegion)
        // Keep lastKnownMapRegion stable during gesture updates.
        // It is refreshed by handleMapCameraChange(.onEnd) after gesture settles,
        // which avoids high-frequency marker overlap regrouping while panning.
    }

    private func shouldIgnoreTransientMapPositionAfterCalendarDismiss(_ region: MKCoordinateRegion) -> Bool {
        let now = Date()
        guard now <= suppressMapInteractionUpdatesUntil,
              let baseline = normalizedRegion(lastKnownMapRegion ?? mapCameraPosition.region) else {
            return false
        }
        let movedKm = distanceKm(from: baseline.center, to: region.center)
        let zoomRatio = zoomScaleRatio(from: baseline.span, to: region.span)
        let isZoomingInAggressively = region.span.latitudeDelta < baseline.span.latitudeDelta * 0.55 &&
            region.span.longitudeDelta < baseline.span.longitudeDelta * 0.55
        guard movedKm <= calendarDismissTransientCenterToleranceKm,
              isZoomingInAggressively,
              zoomRatio >= calendarDismissTransientZoomRatioThreshold else {
            return false
        }
        debugLog(
            "ignoreMapPosition reason=calendarDismissTransientZoom movedKm=\(movedKm) zoomRatio=\(zoomRatio)"
        )
        return true
    }

    private func shouldIgnoreStaleMapPositionDuringProgrammaticMove(
        _ region: MKCoordinateRegion,
        now: Date
    ) -> Bool {
        if now > pendingProgrammaticCameraExpiresAt {
            clearProgrammaticCameraChangeTarget()
            return false
        }
        guard let target = pendingProgrammaticCameraTargetRegion else {
            return false
        }
        let source = pendingProgrammaticCameraSource ?? "programmatic"
        guard shouldBlockStaleProgrammaticCameraChange(for: source) else {
            return false
        }
        let centerDistanceKm = distanceKm(from: target.center, to: region.center)
        let latSpanDiff = abs(target.span.latitudeDelta - region.span.latitudeDelta)
        let lngSpanDiff = abs(target.span.longitudeDelta - region.span.longitudeDelta)
        guard centerDistanceKm > programmaticCameraCenterToleranceKm ||
              latSpanDiff > programmaticCameraSpanTolerance ||
              lngSpanDiff > programmaticCameraSpanTolerance else {
            return false
        }
        debugLog(
            "ignoreMapPosition reason=staleProgrammaticInteraction centerDistanceKm=\(centerDistanceKm)"
        )
        return true
    }

    private func shouldBlockStaleProgrammaticCameraChange(for source: String) -> Bool {
        source.hasPrefix("resetLocation") || source == "forceMapViewRebuild"
    }

    private func setProgrammaticMapPosition(
        _ position: MapCameraPosition,
        source: String = "setProgrammaticMapPosition",
        suppressionWindow: TimeInterval? = nil
    ) {
        maybeRebuildMapViewIfNeeded(nextPosition: position)
        objectWillChange.send()
        mapCameraPosition = position
        if let region = position.region,
           let normalizedTargetRegion = normalizedRegion(region) {
            lastKnownMapRegion = normalizedTargetRegion
            registerProgrammaticCameraChangeTarget(
                normalizedTargetRegion,
                source: source,
                suppressionWindow: suppressionWindow
            )
        }
    }

    private func maybeRebuildMapViewIfNeeded(nextPosition: MapCameraPosition) {
        guard let previousRegion = mapCameraPosition.region ?? lastKnownMapRegion,
              let nextRegion = nextPosition.region else {
            return
        }

        let distanceKm = distanceKm(from: previousRegion.center, to: nextRegion.center)
        guard distanceKm >= mapRebuildDistanceKm else {
            return
        }

        // 跨区域大跳转时重建 Map 实例，直接钉在目标区域，避免先渲染旧视野再跳转造成闪烁/回拉。
        forceMapViewRebuild(
            reason: "longDistanceJump:\(Int(distanceKm.rounded()))km",
            pinnedRegion: nextRegion
        )
    }

    private func forceMapViewRebuild(reason: String, pinnedRegion: MKCoordinateRegion? = nil) {
        var resolvedPinnedRegion: MKCoordinateRegion?
        if let pinnedRegion = normalizedRegion(pinnedRegion ?? mapCameraPosition.region ?? lastKnownMapRegion) {
            resolvedPinnedRegion = pinnedRegion
            mapCameraPosition = .region(pinnedRegion)
            lastKnownMapRegion = pinnedRegion
            registerProgrammaticCameraChangeTarget(
                pinnedRegion,
                source: "forceMapViewRebuild",
                suppressionWindow: 0.35
            )
            lastMapRecycleCenter = pinnedRegion.center
            lastMapRecycleSpan = pinnedRegion.span
            lastHardRecycleCenter = pinnedRegion.center
        }
        mapViewInstanceID = UUID()
        lastViewportQuerySignature = nil
        lastLoadedExpandedRegion = nil
        nearbyLoadTask?.cancel()
        nearbyLoadTask = nil
        activeNearbyQueryToken = nil
        markerEntriesCacheKey = nil
        markerEntriesCache = []
        markerEntriesIndexByID = [:]
        invalidateAllPlacesDerivedCaches()
        cameraMoveCountSinceHardRecycle = 0
        lastHardRecycleAt = Date()
        lastIdleTrimAt = Date()
        hasSignificantMoveSinceLastRecycle = false
        if let resolvedPinnedRegion {
            scheduleViewportReload(
                for: resolvedPinnedRegion,
                reason: "mapRebuild",
                debounceNanoseconds: 0
            )
        }
        debugLog("forceMapViewRebuild reason=\(reason)")
    }

    private func registerMemoryWarningObserverIfNeeded() {
        guard memoryWarningObserver == nil else {
            return
        }
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let currentMemoryMB = self.currentAppMemoryUsageMB() {
                    self.debugLog("systemMemoryWarning currentMemoryMB=\(Int(currentMemoryMB.rounded()))")
                }
                self.forceMapViewRebuild(
                    reason: "systemMemoryWarning",
                    pinnedRegion: self.lastKnownMapRegion
                )
            }
        }
    }

    private func currentAppMemoryUsageMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kern: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard kern == KERN_SUCCESS else {
            return nil
        }
        return Double(info.phys_footprint) / 1_048_576
    }

    private func distanceKm(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let start = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let end = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return start.distance(from: end) / 1_000
    }

    private func zoomScaleRatio(from baseline: MKCoordinateSpan, to current: MKCoordinateSpan) -> Double {
        let baselineLat = max(baseline.latitudeDelta, 0.000_001)
        let baselineLng = max(baseline.longitudeDelta, 0.000_001)
        let currentLat = max(current.latitudeDelta, 0.000_001)
        let currentLng = max(current.longitudeDelta, 0.000_001)

        let latRatio = max(currentLat / baselineLat, baselineLat / currentLat)
        let lngRatio = max(currentLng / baselineLng, baselineLng / currentLng)
        return max(latRatio, lngRatio)
    }

    private func normalizedRegion(_ region: MKCoordinateRegion?) -> MKCoordinateRegion? {
        guard let region else { return nil }
        let lat = region.center.latitude
        let lng = region.center.longitude
        guard lat.isFinite, lng.isFinite else { return nil }
        let spanLat = region.span.latitudeDelta
        let spanLng = region.span.longitudeDelta
        guard spanLat.isFinite, spanLng.isFinite else { return nil }

        let clampedCenter = CLLocationCoordinate2D(
            latitude: min(max(lat, -85), 85),
            longitude: min(max(lng, -180), 180)
        )
        let clampedSpan = MKCoordinateSpan(
            latitudeDelta: min(max(spanLat, 0.0006), 35),
            longitudeDelta: min(max(spanLng, 0.0006), 35)
        )
        return MKCoordinateRegion(center: clampedCenter, span: clampedSpan)
    }

    private func ensureRenderedContains(_ place: HePlace) {
        if renderedPlaces.contains(where: { $0.id == place.id }) {
            return
        }
        var next = renderedPlaces
        next.insert(place, at: 0)
        if next.count > maxRenderedPlaces {
            next = Array(next.prefix(maxRenderedPlaces))
        }
        replaceRenderedPlaces(next)
    }

    private func mutateInteractionState(_ block: () -> Void, notify: Bool = true) {
        if notify {
            objectWillChange.send()
        }
        block()
        placeDecorationStore.retainOnly(placeID: _selectedPlaceID)
    }

    private func focusedCenter(for place: HePlace) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: place.coordinate.latitude + focusedCenterLatitudeOffset,
            longitude: place.coordinate.longitude
        )
    }

    private func isMapAlreadyFocusedForQuickCard(on place: HePlace) -> Bool {
        guard let region = mapCameraPosition.region else {
            return false
        }
        let target = focusedCenter(for: place)
        let centerTolerance: CLLocationDegrees = 0.00028
        let spanTolerance: CLLocationDegrees = 0.0012

        return abs(region.center.latitude - target.latitude) <= centerTolerance &&
            abs(region.center.longitude - target.longitude) <= centerTolerance &&
            abs(region.span.latitudeDelta - focusedMapSpan.latitudeDelta) <= spanTolerance &&
            abs(region.span.longitudeDelta - focusedMapSpan.longitudeDelta) <= spanTolerance
    }

    private func nonExpandingFocusedRegion(for place: HePlace) -> MKCoordinateRegion {
        return MKCoordinateRegion(
            center: focusedCenter(for: place),
            span: focusedMapSpan
        )
    }

    private func shouldFocusQuickCard(place: HePlace) -> Bool {
        !isMapAlreadyFocusedForQuickCard(on: place)
    }

    deinit {
        if let memoryWarningObserver {
            NotificationCenter.default.removeObserver(memoryWarningObserver)
        }
        autoOpenTask?.cancel()
        bootstrapTask?.cancel()
        deferredLoadAllTask?.cancel()
        loadAllTask?.cancel()
        deferredCameraEndTask?.cancel()
        viewportReloadTask?.cancel()
        idleRecycleTask?.cancel()
        periodicHardRecycleTask?.cancel()
        memoryWatchdogTask?.cancel()
        nearbyLoadTask?.cancel()
        nearbyPreheatTask?.cancel()
        activeNearbyQueryToken = nil
        mapZoomRestoreTask?.cancel()
        quickCardPresentationTask?.cancel()
        startReminderSyncTask?.cancel()
        nearbyReminderSyncTask?.cancel()
        topNoticeDismissTask?.cancel()
    }
}
