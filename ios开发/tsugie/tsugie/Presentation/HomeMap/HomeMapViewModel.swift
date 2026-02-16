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
    private struct MarkerEntriesCacheKey: Equatable {
        let placesRevision: UInt64
        let filter: MapPlaceCategoryFilter
        let selectedPlaceID: UUID?
        let markerActionPlaceID: UUID?
        let isDetailVisible: Bool
        let visibleMenuState: PlaceState?
    }

    private struct ViewportQuerySignature: Equatable {
        let centerLatE5: Int
        let centerLngE5: Int
        let spanLatE5: Int
        let spanLngE5: Int
        let filter: MapPlaceCategoryFilter

        init(region: MKCoordinateRegion, filter: MapPlaceCategoryFilter) {
            centerLatE5 = Int((region.center.latitude * 100_000).rounded())
            centerLngE5 = Int((region.center.longitude * 100_000).rounded())
            spanLatE5 = Int((region.span.latitudeDelta * 100_000).rounded())
            spanLngE5 = Int((region.span.longitudeDelta * 100_000).rounded())
            self.filter = filter
        }
    }

    private var mapCameraPosition: MapCameraPosition
    @Published private(set) var mapViewInstanceID = UUID()
    @Published private(set) var places: [HePlace]
    @Published private(set) var renderedPlaces: [HePlace]
    private var _selectedPlaceID: UUID?
    private var _markerActionPlaceID: UUID?
    private var _quickCardPlaceID: UUID?
    private var _detailPlaceID: UUID?
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
    private let mapRebuildDistanceKm: Double = 250
    private let minimumViewportRadiusKm: Double
    private let nearbyLimit: Int
    private let mapBufferScale: Double = 1.8
    private var shouldBootstrapFromBundled: Bool
    private var isLoadingAllPlaces = false
    private var didLoadAllPlaces = false
    private var resolvedCenter: CLLocationCoordinate2D
    private var autoOpenTask: DispatchWorkItem?
    private var bootstrapTask: Task<Void, Never>?
    private var loadAllTask: Task<Void, Never>?
    private var viewportReloadTask: Task<Void, Never>?
    private var nearbyLoadTask: Task<[HePlace], Never>?
    private var activeNearbyQueryToken: UUID?
    private var lastViewportQuerySignature: ViewportQuerySignature?
    private var mapZoomRestoreTask: Task<Void, Never>?
    private var quickCardPresentationTask: Task<Void, Never>?
    private var lastKnownMapRegion: MKCoordinateRegion?
    private var placesRevision: UInt64 = 1
    private var markerEntriesCacheKey: MarkerEntriesCacheKey?
    private var markerEntriesCache: [MapMarkerEntry] = []
    private var markerEntriesIndexByID: [UUID: Int] = [:]
    private var hasAutoOpened = false
    private var ignoreMapTapUntil: Date?
    private let quickCardPresentationAnimation = Animation.spring(response: 0.24, dampingFraction: 0.92)
    private let quickCardDismissAnimation = Animation.spring(response: 0.40, dampingFraction: 0.92)

    init(
        places: [HePlace]? = nil,
        placeStateStore: PlaceStateStore? = nil,
        locationProvider: AppLocationProviding? = nil,
        minimumViewportRadiusKm: Double = 1.2,
        nearbyLimit: Int = 240
    ) {
        let sourcePlaces = (places ?? [])
            .filter { $0.heType != .nature }
        self.places = sourcePlaces
        self.renderedPlaces = sourcePlaces
        self.placeStateStore = placeStateStore ?? PlaceStateStore()
        self.locationProvider = locationProvider ?? DefaultAppLocationProvider()
        self.minimumViewportRadiusKm = max(0.5, minimumViewportRadiusKm)
        self.nearbyLimit = max(1, nearbyLimit)
        self.shouldBootstrapFromBundled = places == nil
        self.resolvedCenter = initialCenter
        self.placesRevision = 1

        let region = MKCoordinateRegion(
            center: initialCenter,
            span: defaultMapSpan
        )
        self.mapCameraPosition = .region(region)
        self.lastKnownMapRegion = region
    }

    var mapPosition: MapCameraPosition {
        mapCameraPosition
    }

    var now: Date {
        Date()
    }

    var quickCardPlace: HePlace? {
        guard let quickCardPlaceID = _quickCardPlaceID else {
            return nil
        }
        return place(for: quickCardPlaceID)
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

    func onViewAppear() {
        debugLog("onViewAppear allPlaces=\(self.places.count) renderedPlaces=\(self.renderedPlaces.count) mapFilter=\(self.mapCategoryFilter.rawValue)")
        bootstrapNearbyPlacesIfNeeded()
        scheduleAutoOpenIfNeeded()
    }

    func onViewDisappear() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        viewportReloadTask?.cancel()
        viewportReloadTask = nil
        nearbyLoadTask?.cancel()
        nearbyLoadTask = nil
        activeNearbyQueryToken = nil
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
        }
    }

    func tapMarker(placeID: UUID) {
        guard _detailPlaceID == nil else { return }
        markAnnotationTapCooldown()
        cancelPendingQuickCardPresentation()
        cancelPendingMapZoomRestore()
        cancelPendingMapFocus()

        if _selectedPlaceID == placeID {
            withAnimation(quickCardDismissAnimation) {
                closeQuickCard(restoreMapZoom: false)
            }
            return
        }

        let targetPlace = place(for: placeID)
        let focusPlace = targetPlace.flatMap { place in
            isMapAlreadyFocusedForQuickCard(on: place) ? nil : place
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

    func closeMarkerActionBubble() {
        dismissMarkerSelection(restoreMapZoom: false)
    }

    func markAnnotationTapCooldown(_ duration: TimeInterval = 0.08) {
        ignoreMapTapUntil = Date().addingTimeInterval(duration)
    }

    func handleMapBackgroundTap() {
        if let until = ignoreMapTapUntil, Date() < until {
            return
        }
        if _quickCardPlaceID != nil {
            withAnimation(quickCardDismissAnimation) {
                closeQuickCard(restoreMapZoom: true)
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
        cancelPendingMapZoomRestore()
        mutateInteractionState {
            _selectedPlaceID = placeID
            _markerActionPlaceID = keepMarkerActions ? placeID : nil
            _detailPlaceID = nil
            _quickCardPlaceID = showPanel ? placeID : nil
            if let focusPlace {
                mapCameraPosition = .region(
                    MKCoordinateRegion(
                        center: focusedCenter(for: focusPlace),
                        span: focusedMapSpan
                    )
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
            if shouldDismissMarkerSelection {
                _markerActionPlaceID = nil
                _selectedPlaceID = nil
            }
        }

        if shouldDismissMarkerSelection, restoreMapZoom {
            scheduleMapZoomRestoreAfterQuickDismiss(focusedPlaceID: focusedPlaceID)
        }
    }

    func selectPlaceFromCarousel(placeID: UUID) {
        guard _detailPlaceID == nil else { return }
        cancelPendingQuickCardPresentation()
        cancelPendingMapZoomRestore()
        cancelPendingMapFocus()
        let targetPlace = place(for: placeID)
        let focusPlace = targetPlace.flatMap { place in
            isMapAlreadyFocusedForQuickCard(on: place) ? nil : place
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
        guard let quickCardPlaceID = _quickCardPlaceID else {
            return
        }
        mutateInteractionState {
            _detailPlaceID = quickCardPlaceID
            _selectedPlaceID = quickCardPlaceID
            _markerActionPlaceID = nil
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
        if !isSideDrawerOpen {
            isSideDrawerOpen = true
        }
        if sideDrawerMenu != .none {
            sideDrawerMenu = .none
        }
        if isThemePaletteOpen {
            isThemePaletteOpen = false
        }
        closeMarkerActionBubble()
    }

    func closeSideDrawerPanel() {
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

    func closeSideDrawerBackdrop() {
        if isFavoriteDrawerOpen {
            isFavoriteDrawerOpen = false
            return
        }
        closeSideDrawerPanel()
    }

    func setSideDrawerMenu(_ menu: SideDrawerMenu) {
        if !isSideDrawerOpen {
            isSideDrawerOpen = true
        }
        if sideDrawerMenu != menu {
            sideDrawerMenu = menu
        }
        if menu == .favorites {
            if favoriteFilter != .all {
                favoriteFilter = .all
            }
            if !isFavoriteDrawerOpen {
                isFavoriteDrawerOpen = true
            }
        } else {
            if isFavoriteDrawerOpen {
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

    func mapMarkerEntries() -> [MapMarkerEntry] {
        let isDetailVisible = _detailPlaceID != nil
        let visibleMenuState: PlaceState? = {
            guard !isDetailVisible, let placeID = _markerActionPlaceID else {
                return nil
            }
            return placeStateStore.state(for: placeID)
        }()

        let cacheKey = MarkerEntriesCacheKey(
            placesRevision: placesRevision,
            filter: mapCategoryFilter,
            selectedPlaceID: _selectedPlaceID,
            markerActionPlaceID: _markerActionPlaceID,
            isDetailVisible: isDetailVisible,
            visibleMenuState: visibleMenuState
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

        let entries = mapPlaces().map { place in
            let isMenuVisible = _markerActionPlaceID == place.id && !isDetailVisible
            return MapMarkerEntry(
                id: place.id,
                name: place.name,
                coordinate: place.coordinate,
                heType: place.heType,
                isSelected: _selectedPlaceID == place.id,
                isMenuVisible: isMenuVisible,
                menuPlaceState: isMenuVisible ? placeState(for: place.id) : nil
            )
        }

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
              previousKey.filter == nextKey.filter,
              !markerEntriesCache.isEmpty,
              !markerEntriesIndexByID.isEmpty else {
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
                isSelected: nextIsSelected,
                isMenuVisible: nextIsMenuVisible,
                menuPlaceState: nextMenuState
            )
        }
        return updated
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
        let full = places.isEmpty ? renderedPlaces : places
        switch filter {
        case .all:
            return full.count
        case .hanabi:
            return full.filter { $0.heType == .hanabi }.count
        case .matsuri:
            return full.filter { $0.heType == .matsuri }.count
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
        forceMapViewRebuild(reason: "userResetLocation")
        reloadNearbyPlacesAroundCurrentLocation(userInitiated: true)
    }

    func focus(on place: HePlace) {
        withAnimation(.easeInOut(duration: 0.25)) {
            setProgrammaticMapPosition(.region(
                MKCoordinateRegion(
                    center: place.coordinate,
                    span: focusedMapSpan
                )
            ))
        }
    }

    func eventStatus(for place: HePlace, now: Date = Date()) -> EventStatus {
        EventStatusResolver.resolve(startAt: place.startAt, endAt: place.endAt, now: now)
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
        let source = places.isEmpty ? renderedPlaces : places
        return source
            .filter { placeState(for: $0.id).isFavorite }
            .sorted(by: isHigherPriority)
    }

    func place(for placeID: UUID) -> HePlace? {
        if let matched = places.first(where: { $0.id == placeID }) {
            return matched
        }
        return renderedPlaces.first(where: { $0.id == placeID })
    }

    func focusForBottomCard(on place: HePlace) {
        withAnimation(.easeOut(duration: 0.24)) {
            setProgrammaticMapPosition(.region(
                MKCoordinateRegion(
                    center: focusedCenter(for: place),
                    span: focusedMapSpan
                )
            ))
        }
    }

    func nearbyPlaces(limit: Int = 10) -> [HePlace] {
        Array(mapPlaces().sorted(by: isCloserAndEarlier).prefix(limit))
    }

    func nearbyCarouselItems(now: Date, limit: Int = 10) -> [NearbyCarouselItemModel] {
        nearbyPlaces(limit: limit).map { place in
            NearbyCarouselItemModel(
                id: place.id,
                name: place.name,
                snapshot: eventSnapshot(for: place, now: now),
                distanceText: distanceText(for: place),
                placeState: placeState(for: place.id)
            )
        }
    }

    func mapPlaces() -> [HePlace] {
        switch mapCategoryFilter {
        case .all:
            return renderedPlaces
        case .hanabi:
            return renderedPlaces.filter { $0.heType == .hanabi }
        case .matsuri:
            return renderedPlaces.filter { $0.heType == .matsuri }
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
        let nextDetailPlaceID = _detailPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextQuickCardPlaceID = _quickCardPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextMarkerActionPlaceID = _markerActionPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }
        let nextSelectedPlaceID = _selectedPlaceID.flatMap { visiblePlaceIDs.contains($0) ? $0 : nil }

        let changed =
            nextDetailPlaceID != _detailPlaceID ||
            nextQuickCardPlaceID != _quickCardPlaceID ||
            nextMarkerActionPlaceID != _markerActionPlaceID ||
            nextSelectedPlaceID != _selectedPlaceID

        guard changed else {
            return
        }

        mutateInteractionState {
            _detailPlaceID = nextDetailPlaceID
            _quickCardPlaceID = nextQuickCardPlaceID
            _markerActionPlaceID = nextMarkerActionPlaceID
            _selectedPlaceID = nextSelectedPlaceID
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
            guard self._quickCardPlaceID == nil,
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

    private func bootstrapNearbyPlacesIfNeeded() {
        if shouldBootstrapFromBundled {
            reloadNearbyPlacesAroundCurrentLocation(userInitiated: false)
            return
        }

        loadAllPlacesIfNeeded(center: resolvedCenter)
        if let region = mapCameraPosition.region {
            scheduleViewportReload(for: region, reason: "viewAppear", debounceNanoseconds: 0)
        }
    }

    private func reloadNearbyPlacesAroundCurrentLocation(userInitiated: Bool) {
        if !userInitiated, bootstrapTask != nil {
            return
        }

        bootstrapTask?.cancel()
        bootstrapTask = Task { [weak self] in
            guard let self else { return }

            let center = await self.locationProvider.currentCoordinate(fallback: self.initialCenter)

            guard !Task.isCancelled else {
                return
            }

            self.bootstrapTask = nil
            self.resolvedCenter = center

            let targetRegion = MKCoordinateRegion(
                center: center,
                span: self.defaultMapSpan
            )
            if userInitiated {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.setProgrammaticMapPosition(.region(targetRegion))
                }
            }

            self.loadAllPlacesIfNeeded(center: center)
            self.scheduleViewportReload(
                for: targetRegion,
                reason: userInitiated ? "resetLocation" : "bootstrap",
                debounceNanoseconds: userInitiated ? 0 : 30_000_000
            )
            self.shouldBootstrapFromBundled = false
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
    }

    private func replaceRenderedPlaces(_ newPlaces: [HePlace]) {
        renderedPlaces = newPlaces
        placesRevision &+= 1
        markerEntriesCacheKey = nil
        markerEntriesCache = []
        markerEntriesIndexByID = [:]
        reconcileSelectionForMapFilter()
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
        lastKnownMapRegion = region
        scheduleViewportReload(for: region, reason: "cameraMove", debounceNanoseconds: 220_000_000)
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
        let searchCenter = expandedRegion.center
        let userCenter = resolvedCenter

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

        lastViewportQuerySignature = signature
        let normalized = normalizedPlaces(loaded, fallbackToMockWhenEmpty: reason == "bootstrap")
        let inRegion = filteredPlacesInRegion(normalized, region: expandedRegion)
        let rendered = rebasedDistancePlaces(inRegion, center: userCenter)
        debugLog(
            "reloadRendered reason=\(reason) center=(\(region.center.latitude),\(region.center.longitude)) span=(\(region.span.latitudeDelta),\(region.span.longitudeDelta)) rawQueryRadiusKm=\(rawQueryRadiusKm) queryRadiusKm=\(queryRadiusKm) queryLimit=\(queryLimit) loaded=\(loaded.count) normalized=\(normalized.count) inRegion=\(inRegion.count) rendered=\(rendered.count)"
        )
        replaceRenderedPlaces(rendered)
        if places.isEmpty, !rendered.isEmpty {
            replaceAllPlaces(rendered)
        }
        if !rendered.isEmpty {
            scheduleAutoOpenIfNeeded()
        }
    }

    private func rebasedDistancePlaces(_ source: [HePlace], center: CLLocationCoordinate2D) -> [HePlace] {
        let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return source.map { place in
            let placeLocation = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            let distance = centerLocation.distance(from: placeLocation)
            return HePlace(
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
                imageTag: place.imageTag,
                imageHint: place.imageHint,
                heatScore: place.heatScore,
                surpriseScore: place.surpriseScore
            )
        }
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
        let halfLat = region.span.latitudeDelta / 2
        let halfLng = region.span.longitudeDelta / 2
        return source.filter { place in
            abs(place.coordinate.latitude - region.center.latitude) <= halfLat &&
                abs(place.coordinate.longitude - region.center.longitude) <= halfLng
        }
    }

    private func restoreMapZoomAfterSelectionIfNeeded(focusedPlaceID: UUID?) {
        guard let focusedPlaceID,
              let place = place(for: focusedPlaceID) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            setProgrammaticMapPosition(.region(
                MKCoordinateRegion(
                    center: focusedCenter(for: place),
                    span: defaultMapSpan
                )
            ))
        }
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
        mapCameraPosition = position
    }

    private func setProgrammaticMapPosition(_ position: MapCameraPosition) {
        maybeRebuildMapViewIfNeeded(nextPosition: position)
        objectWillChange.send()
        mapCameraPosition = position
        if let region = position.region {
            lastKnownMapRegion = region
        }
    }

    private func maybeRebuildMapViewIfNeeded(nextPosition: MapCameraPosition) {
        guard let previousRegion = mapCameraPosition.region ?? lastKnownMapRegion,
              let nextRegion = nextPosition.region else {
            return
        }

        let previous = CLLocation(latitude: previousRegion.center.latitude, longitude: previousRegion.center.longitude)
        let next = CLLocation(latitude: nextRegion.center.latitude, longitude: nextRegion.center.longitude)
        let distanceKm = previous.distance(from: next) / 1_000
        guard distanceKm >= mapRebuildDistanceKm else {
            return
        }

        // 跨区域大跳转时重建 Map 实例，避免旧瓦片/渲染缓存长期堆积。
        forceMapViewRebuild(reason: "longDistanceJump:\(Int(distanceKm.rounded()))km")
    }

    private func forceMapViewRebuild(reason: String) {
        mapViewInstanceID = UUID()
        lastViewportQuerySignature = nil
        nearbyLoadTask?.cancel()
        nearbyLoadTask = nil
        activeNearbyQueryToken = nil
        debugLog("forceMapViewRebuild reason=\(reason)")
    }

    private func mutateInteractionState(_ block: () -> Void, notify: Bool = true) {
        if notify {
            objectWillChange.send()
        }
        block()
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

    deinit {
        autoOpenTask?.cancel()
        bootstrapTask?.cancel()
        loadAllTask?.cancel()
        viewportReloadTask?.cancel()
        nearbyLoadTask?.cancel()
        activeNearbyQueryToken = nil
        mapZoomRestoreTask?.cancel()
        quickCardPresentationTask?.cancel()
    }
}
