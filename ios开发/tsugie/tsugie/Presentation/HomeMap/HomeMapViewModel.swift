import CoreLocation
import Combine
import MapKit
import os
import SwiftUI

enum SideDrawerMenu: String, CaseIterable {
    case none
    case favorites
    case notifications
    case contact
}

enum FavoriteDrawerFilter: String, CaseIterable {
    case all
    case planned
    case checked
}

enum MapPlaceCategoryFilter: String, CaseIterable {
    case all
    case hanabi
    case matsuri
}

@MainActor
final class HomeMapViewModel: ObservableObject {
    @Published var mapPosition: MapCameraPosition
    @Published private(set) var places: [HePlace]
    @Published private(set) var selectedPlaceID: UUID?
    @Published private(set) var markerActionPlaceID: UUID?
    @Published private(set) var quickCardPlaceID: UUID?
    @Published private(set) var detailPlaceID: UUID?
    @Published private(set) var now: Date = Date()
    @Published private(set) var isCalendarPresented = false
    @Published private(set) var isSideDrawerOpen = false
    @Published private(set) var isFavoriteDrawerOpen = false
    @Published private(set) var sideDrawerMenu: SideDrawerMenu = .none
    @Published private(set) var favoriteFilter: FavoriteDrawerFilter = .all
    @Published private(set) var mapCategoryFilter: MapPlaceCategoryFilter = .all
    @Published var isThemePaletteOpen = false
    @Published var selectedThemeScheme = "fresh"
    @Published var themeAlphaRatio: Double = 1
    @Published var themeSaturationRatio: Double = 1
    @Published var themeGlowRatio: Double = 1
    @Published var selectedLanguageCode: String = L10n.languageCode
    @Published var worldMode = false
    @Published var startNotificationEnabled = true
    @Published var nearbyNotificationEnabled = false

    private let logger = Logger(subsystem: "com.ushouldknowr0.tsugie", category: "HomeMapViewModel")
    private let placeStateStore: PlaceStateStore
    private let locationProvider: AppLocationProviding
    private let initialCenter = DefaultAppLocationProvider.developmentFixedCoordinate
    private let defaultMapSpan = MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    private let focusedMapSpan = MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
    private let focusedCenterLatitudeOffset: CLLocationDegrees = 0.0023
    private let nearbyRadiusKm: Double
    private let nearbyLimit: Int
    private var shouldBootstrapFromBundled: Bool
    private var resolvedCenter: CLLocationCoordinate2D
    private var autoOpenTask: DispatchWorkItem?
    private var tickerCancellable: AnyCancellable?
    private var bootstrapTask: Task<Void, Never>?
    private var hasAutoOpened = false
    private var ignoreMapTapUntil: Date?

    init(
        places: [HePlace]? = nil,
        placeStateStore: PlaceStateStore? = nil,
        locationProvider: AppLocationProviding? = nil,
        nearbyRadiusKm: Double = 30,
        nearbyLimit: Int = 700
    ) {
        self.places = (places ?? [])
            .filter { $0.heType != .nature }
        self.placeStateStore = placeStateStore ?? PlaceStateStore()
        self.locationProvider = locationProvider ?? DefaultAppLocationProvider()
        self.nearbyRadiusKm = max(1, nearbyRadiusKm)
        self.nearbyLimit = max(1, nearbyLimit)
        self.shouldBootstrapFromBundled = places == nil
        self.resolvedCenter = initialCenter

        let region = MKCoordinateRegion(
            center: initialCenter,
            span: defaultMapSpan
        )
        self.mapPosition = .region(region)
    }

    var quickCardPlace: HePlace? {
        guard let quickCardPlaceID else {
            return nil
        }
        return places.first { $0.id == quickCardPlaceID }
    }

    var detailPlace: HePlace? {
        guard let detailPlaceID else {
            return nil
        }
        return places.first { $0.id == detailPlaceID }
    }

    var isDetailVisible: Bool {
        detailPlaceID != nil
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

    func onViewAppear() {
        debugLog("onViewAppear places=\(self.places.count) mapFilter=\(self.mapCategoryFilter.rawValue)")
        startStatusTicker()
        bootstrapNearbyPlacesIfNeeded()
        scheduleAutoOpenIfNeeded()
    }

    func onViewDisappear() {
        tickerCancellable?.cancel()
        tickerCancellable = nil
        bootstrapTask?.cancel()
        bootstrapTask = nil
    }

    func setCalendarPresented(_ presented: Bool) {
        isCalendarPresented = presented
        if presented {
            closeSideDrawerPanel()
            closeMarkerActionBubble()
        }
    }

    func tapMarker(placeID: UUID) {
        guard detailPlaceID == nil else { return }
        markAnnotationTapCooldown()

        if selectedPlaceID == placeID {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                closeQuickCard()
            }
            return
        }

        if let place = place(for: placeID) {
            focusForBottomCard(on: place)
        }

        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            openQuickCard(placeID: placeID, keepMarkerActions: true)
        }
    }

    func closeMarkerActionBubble() {
        dismissMarkerSelection()
    }

    func markAnnotationTapCooldown(_ duration: TimeInterval = 0.22) {
        ignoreMapTapUntil = Date().addingTimeInterval(duration)
    }

    func handleMapBackgroundTap() {
        if let until = ignoreMapTapUntil, Date() < until {
            return
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            dismissMarkerSelection()
        }
    }

    private func dismissMarkerSelection() {
        let focusedPlaceID = selectedPlaceID
        markerActionPlaceID = nil
        selectedPlaceID = nil
        if detailPlaceID == nil {
            restoreMapZoomAfterSelectionIfNeeded(focusedPlaceID: focusedPlaceID)
        }
    }

    func openQuickCard(placeID: UUID, keepMarkerActions: Bool = false) {
        selectedPlaceID = placeID
        markerActionPlaceID = keepMarkerActions ? placeID : nil
        detailPlaceID = nil
        quickCardPlaceID = placeID
    }

    func closeQuickCard() {
        quickCardPlaceID = nil
        if detailPlaceID == nil {
            dismissMarkerSelection()
        }
    }

    func openDetailForCurrentQuickCard() {
        guard let quickCardPlaceID else {
            return
        }
        detailPlaceID = quickCardPlaceID
        selectedPlaceID = quickCardPlaceID
        markerActionPlaceID = nil
    }

    func closeDetail() {
        detailPlaceID = nil
    }

    func toggleSideDrawerPanel() {
        if isSideDrawerOpen {
            closeSideDrawerPanel()
            return
        }
        isSideDrawerOpen = true
        sideDrawerMenu = .none
        isThemePaletteOpen = false
        closeMarkerActionBubble()
    }

    func closeSideDrawerPanel() {
        isSideDrawerOpen = false
        isFavoriteDrawerOpen = false
        sideDrawerMenu = .none
        isThemePaletteOpen = false
    }

    func closeSideDrawerBackdrop() {
        if isFavoriteDrawerOpen {
            isFavoriteDrawerOpen = false
            return
        }
        closeSideDrawerPanel()
    }

    func setSideDrawerMenu(_ menu: SideDrawerMenu) {
        isSideDrawerOpen = true
        sideDrawerMenu = menu
        if menu == .favorites {
            favoriteFilter = .all
            isFavoriteDrawerOpen = true
        } else {
            isFavoriteDrawerOpen = false
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
        isSideDrawerOpen = true
        sideDrawerMenu = .favorites
        favoriteFilter = .all
        isFavoriteDrawerOpen = true
    }

    func closeFavoriteDrawer() {
        isFavoriteDrawerOpen = false
    }

    func setFavoriteFilter(_ filter: FavoriteDrawerFilter) {
        favoriteFilter = filter
    }

    func setMapCategoryFilter(_ filter: MapPlaceCategoryFilter) {
        mapCategoryFilter = filter
        reconcileSelectionForMapFilter()
    }

    func filteredFavoritePlaces() -> [HePlace] {
        let favorites = favoritePlaces()
        return filteredFavoritePlacesByStatus(from: favorites)
    }

    func favoriteFilterCount(_ filter: FavoriteDrawerFilter) -> Int {
        let favorites = favoritePlaces()
        switch filter {
        case .all:
            return favorites.count
        case .planned:
            return favorites.filter { !placeState(for: $0.id).isCheckedIn }.count
        case .checked:
            return favorites.filter { placeState(for: $0.id).isCheckedIn }.count
        }
    }

    func mapCategoryFilterCount(_ filter: MapPlaceCategoryFilter) -> Int {
        let rendered = mapPlaces()
        switch filter {
        case .all:
            return rendered.count
        case .hanabi:
            return rendered.filter { $0.heType == .hanabi }.count
        case .matsuri:
            return rendered.filter { $0.heType == .matsuri }.count
        }
    }

    func openQuickFromDrawer(placeID: UUID) {
        closeSideDrawerPanel()
        openQuickCard(placeID: placeID, keepMarkerActions: true)
    }

    func toggleStartNotification() {
        startNotificationEnabled.toggle()
    }

    func toggleNearbyNotification() {
        nearbyNotificationEnabled.toggle()
    }

    func resetToCurrentLocation() {
        withAnimation(.easeInOut(duration: 0.25)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: resolvedCenter,
                    span: defaultMapSpan
                )
            )
        }
        reloadNearbyPlacesAroundCurrentLocation(userInitiated: true)
    }

    func focus(on place: HePlace) {
        withAnimation(.easeInOut(duration: 0.25)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: place.coordinate,
                    span: focusedMapSpan
                )
            )
        }
    }

    func eventStatus(for place: HePlace, now: Date = Date()) -> EventStatus {
        EventStatusResolver.resolve(startAt: place.startAt, endAt: place.endAt, now: now)
    }

    func eventSnapshot(for place: HePlace, now: Date? = nil) -> EventStatusSnapshot {
        EventStatusResolver.snapshot(startAt: place.startAt, endAt: place.endAt, now: now ?? self.now)
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
        let snapshot = eventSnapshot(for: place, now: now)
        return "\(distanceText(for: place)) ・ \(quickStartDateText(for: snapshot))"
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

    func toggleFavorite(for placeID: UUID) {
        placeStateStore.toggleFavorite(for: placeID)
        objectWillChange.send()
    }

    func toggleCheckedIn(for placeID: UUID) {
        placeStateStore.toggleCheckedIn(for: placeID)
        objectWillChange.send()
    }

    func favoritePlaces() -> [HePlace] {
        places
            .filter { placeState(for: $0.id).isFavorite }
            .sorted(by: isHigherPriority)
    }

    func place(for placeID: UUID) -> HePlace? {
        places.first { $0.id == placeID }
    }

    func focusForBottomCard(on place: HePlace) {
        withAnimation(.easeInOut(duration: 0.25)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: focusedCenter(for: place),
                    span: focusedMapSpan
                )
            )
        }
    }

    func nearbyPlaces(limit: Int = 10) -> [HePlace] {
        Array(mapPlaces().sorted(by: isCloserAndEarlier).prefix(limit))
    }

    func mapPlaces() -> [HePlace] {
        switch mapCategoryFilter {
        case .all:
            return places
        case .hanabi:
            return places.filter { $0.heType == .hanabi }
        case .matsuri:
            return places.filter { $0.heType == .matsuri }
        }
    }

    private func filteredFavoritePlacesByStatus(from places: [HePlace]) -> [HePlace] {
        switch favoriteFilter {
        case .all:
            return places
        case .planned:
            return places.filter { !placeState(for: $0.id).isCheckedIn }
        case .checked:
            return places.filter { placeState(for: $0.id).isCheckedIn }
        }
    }

    private func reconcileSelectionForMapFilter() {
        let visiblePlaceIDs = Set(mapPlaces().map(\.id))

        if let detailPlaceID, !visiblePlaceIDs.contains(detailPlaceID) {
            self.detailPlaceID = nil
        }

        if let quickCardPlaceID, !visiblePlaceIDs.contains(quickCardPlaceID) {
            self.quickCardPlaceID = nil
        }

        if let markerActionPlaceID, !visiblePlaceIDs.contains(markerActionPlaceID) {
            self.markerActionPlaceID = nil
        }

        if let selectedPlaceID, !visiblePlaceIDs.contains(selectedPlaceID) {
            self.selectedPlaceID = nil
        }
    }

    private func quickStartDateText(for snapshot: EventStatusSnapshot) -> String {
        guard let startDate = snapshot.startDate else {
            return L10n.Common.dateUnknown
        }

        if Calendar.current.isDateInToday(startDate) {
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

    private func scheduleAutoOpenIfNeeded() {
        guard autoOpenTask == nil, !hasAutoOpened else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.autoOpenTask = nil
            guard self.quickCardPlaceID == nil,
                  self.detailPlaceID == nil,
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

    private func recommendedPlace() -> HePlace? {
        mapPlaces().sorted(by: isHigherPriority).first
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

    private func startStatusTicker() {
        guard tickerCancellable == nil else {
            return
        }
        tickerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.now = date
            }
    }

    private func bootstrapNearbyPlacesIfNeeded() {
        guard shouldBootstrapFromBundled else {
            return
        }
        reloadNearbyPlacesAroundCurrentLocation(userInitiated: false)
    }

    private func reloadNearbyPlacesAroundCurrentLocation(userInitiated: Bool) {
        if !userInitiated, bootstrapTask != nil {
            return
        }

        bootstrapTask?.cancel()
        bootstrapTask = Task { [weak self] in
            guard let self else { return }

            let center = await self.locationProvider.currentCoordinate(fallback: self.initialCenter)
            let radiusKm = self.nearbyRadiusKm
            let limit = self.nearbyLimit
            let loaded = await Task.detached(priority: .userInitiated) {
                EncodedHePlaceRepository.loadNearby(
                    center: center,
                    radiusKm: radiusKm,
                    limit: limit
                )
            }.value

            guard !Task.isCancelled else {
                return
            }

            self.bootstrapTask = nil
            self.resolvedCenter = center

            let usingMockFallback = loaded.isEmpty
            let normalized = self.normalizedPlaces(loaded)
            self.debugLog(
                "reloadNearby done center=(\(center.latitude),\(center.longitude)) loaded=\(loaded.count) normalized=\(normalized.count) usingMockFallback=\(usingMockFallback)"
            )
            if !normalized.isEmpty {
                self.places = normalized
                self.shouldBootstrapFromBundled = false
                self.scheduleAutoOpenIfNeeded()
            }
        }
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print("[HomeMapViewModel] \(message)")
#endif
        logger.info("\(message, privacy: .public)")
    }

    private func normalizedPlaces(_ loaded: [HePlace]) -> [HePlace] {
        let source = loaded.isEmpty ? MockHePlaceRepository.load() : loaded
        return source.filter { $0.heType != .nature }
    }

    private func restoreMapZoomAfterSelectionIfNeeded(focusedPlaceID: UUID?) {
        guard let focusedPlaceID,
              let place = place(for: focusedPlaceID) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: focusedCenter(for: place),
                    span: defaultMapSpan
                )
            )
        }
    }

    private func focusedCenter(for place: HePlace) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: place.coordinate.latitude + focusedCenterLatitudeOffset,
            longitude: place.coordinate.longitude
        )
    }

    deinit {
        autoOpenTask?.cancel()
        tickerCancellable?.cancel()
        bootstrapTask?.cancel()
    }
}
