import QuartzCore
import SwiftUI

struct CalendarPageView: View {
    let places: [HePlace]
    let detailPlacesProvider: () -> [HePlace]
    let placeStateProvider: (UUID) -> PlaceState
    let stampProvider: (UUID, HeType) -> PlaceStampPresentation?
    let onClose: () -> Void
    let onSelectPlace: (UUID) -> Void
    let now: Date
    let activeGradient: LinearGradient
    let activeGlowColor: Color

    private static let prewarmStoreQueue = DispatchQueue(label: "tsugie.calendar.prewarm.store", qos: .utility)
    private static var prewarmedPayloadsBySignature: [String: CalendarPrewarmedPayload] = [:]

    @State private var selectedDayKey: String?
    @State private var dayFilterID = "all"
    @State private var cachedBucketsByDayKey: [String: CalendarBucket] = [:]
    @State private var cachedDetailPlacesByDayKey: [String: [HePlace]] = [:]
    @State private var cachedDetailItemsByDayKey: [String: [CalendarScoredItem]] = [:]
    @State private var cachedPlacesSignature = ""
    @State private var isCalendarCacheLoading = true
    @State private var calendarCacheBuildToken: Int = 0
    @State private var currentMonthCursor = Calendar.current.startOfDay(for: Date())
    @State private var monthPageDragOffset: CGFloat = 0
    @State private var isMonthPaging = false
    @State private var previousMonthBlock: CalendarMonthBlock?
    @State private var currentMonthBlock: CalendarMonthBlock?
    @State private var nextMonthBlock: CalendarMonthBlock?
    @State private var monthBlockPool: [String: CalendarMonthBlock] = [:]
    @State private var monthBlockPoolBuildToken: Int = 0
    @State private var weekdaySymbolsCache: [String] = Self.defaultWeekdaySymbols
    @State private var dayDrawerVisibleItemLimit = 24
    @State private var loadingDetailDayKeys: Set<String> = []
    private static let dayDrawerPageSize = 24

#if DEBUG
    private static func debugTimestamp() -> CFTimeInterval {
        CACurrentMediaTime()
    }

    private static func debugLog(_ message: String) {
        print("[CalendarPerf] \(message)")
    }
#endif

    static func prewarmCache(
        places: [HePlace],
        now: Date,
        locale: Locale
    ) {
        let signature = makePlacesSignature(places: places)
        let calendar = Calendar.current
        let buckets = buildCalendarBuckets(from: places, calendar: calendar)
        let bucketsByDayKey = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
        let anchorMonth = startOfMonth(now, calendar: calendar)
        let monthPool = buildMonthBlockPool(
            anchorMonth: anchorMonth,
            offsets: -1...1,
            bucketMap: bucketsByDayKey,
            locale: locale,
            calendar: calendar
        )
        let payload = CalendarPrewarmedPayload(
            signature: signature,
            localeIdentifier: locale.identifier,
            bucketsByDayKey: bucketsByDayKey,
            monthBlockPool: monthPool
        )
        prewarmStoreQueue.sync {
            prewarmedPayloadsBySignature[signature] = payload
            if prewarmedPayloadsBySignature.count > 3 {
                let removeCount = prewarmedPayloadsBySignature.count - 3
                let keys = Array(prewarmedPayloadsBySignature.keys.prefix(removeCount))
                for key in keys {
                    prewarmedPayloadsBySignature.removeValue(forKey: key)
                }
            }
        }
    }

    private var categories: [CalendarCategoryMeta] {
        [
            .init(id: "all", label: L10n.Calendar.categoryAll, iconName: TsugieSmallIcon.assetName(for: "all")),
            .init(id: "hanabi", label: L10n.Calendar.categoryHanabi, iconName: TsugieSmallIcon.assetName(for: "hanabi")),
            .init(id: "matsuri", label: L10n.Calendar.categoryMatsuri, iconName: TsugieSmallIcon.assetName(for: "matsuri")),
            .init(id: "nature", label: L10n.Calendar.categoryNature, iconName: TsugieSmallIcon.assetName(for: "nature")),
            .init(id: "other", label: L10n.Calendar.categoryOther, iconName: TsugieSmallIcon.assetName(for: "other"))
        ]
    }
    var body: some View {
        GeometryReader { proxy in
            let topSafeInset = max(proxy.safeAreaInsets.top, 0)

            ZStack {
                backgroundLayer

                VStack(spacing: 0) {
                    header(topSafeInset: topSafeInset)
                    monthList
                }

                if isDayDrawerOpen {
                    dayDrawerLayer(proxy: proxy)
                        .transition(.move(edge: .trailing))
                        .zIndex(8)
                }
            }
            .ignoresSafeArea()
            .onAppear {
                weekdaySymbolsCache = Self.buildWeekdaySymbols(locale: L10n.locale)
                refreshCalendarCacheIfNeeded(force: true)
            }
            .onDisappear {
                calendarCacheBuildToken &+= 1
                monthBlockPoolBuildToken &+= 1
                isMonthPaging = false
                monthPageDragOffset = 0
            }
            .onChange(of: places.count) { _, _ in
                refreshCalendarCacheIfNeeded(force: false)
            }
            .onChange(of: selectedDayKey) { _, _ in
                resetDayDrawerVisibleItemLimit()
            }
            .onChange(of: dayFilterID) { _, _ in
                resetDayDrawerVisibleItemLimit()
            }
            .onChange(of: L10n.locale.identifier) { _, _ in
                weekdaySymbolsCache = Self.buildWeekdaySymbols(locale: L10n.locale)
            }
        }
    }

    private func header(topSafeInset: CGFloat) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.Calendar.title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color(red: 0.19, green: 0.35, blue: 0.42))
            }

            Spacer()

            TsugieClosePillButton(action: onClose, accessibilityLabel: L10n.Calendar.closeA11y)
                .padding(.trailing, 6)
        }
        .padding(.top, topSafeInset + 8)
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.bottom, 8)
    }

    private var monthList: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 36, 1)

            VStack(spacing: 8) {
                if isCalendarCacheLoading {
                    monthListSkeleton
                } else if let previousBlock = previousMonthBlock,
                          let currentBlock = currentMonthBlock,
                          let nextBlock = nextMonthBlock {
                    CalendarMonthPagerView(
                        width: width,
                        previousBlock: previousBlock,
                        currentBlock: currentBlock,
                        nextBlock: nextBlock,
                        weekdaySymbols: weekdaySymbolsCache,
                        monthPageDragOffset: monthPageDragOffset,
                        isMonthPaging: isMonthPaging,
                        todayDayKey: dayKeyOf(now),
                        onSelectDay: handleDaySelection,
                        onDragChanged: { value in
                            handleMonthPagingChanged(value, width: width)
                        },
                        onDragEnded: { value in
                            handleMonthPagingEnded(value, width: width)
                        }
                    )
                    .equatable()
                } else {
                    monthListSkeleton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.leading, 12)
            .padding(.trailing, 24)
            .padding(.bottom, 24)
        }
    }

    private func monthBlockForPage(offset: Int) -> CalendarMonthBlock {
        let calendar = Calendar.current
        let baseMonth = startOfMonth(currentMonthCursor)
        let targetMonth = calendar.date(byAdding: .month, value: offset, to: baseMonth) ?? baseMonth
        let monthKey = Self.calendarMonthKey(targetMonth, calendar: calendar)
        if let pooled = monthBlockPool[monthKey] {
            return pooled
        }
        return Self.buildSingleCalendarMonth(
            monthStart: targetMonth,
            bucketMap: cachedBucketsByDayKey,
            locale: L10n.locale,
            calendar: calendar
        )
    }

    private func handleDaySelection(_ dayKey: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            selectedDayKey = dayKey
        }
        dayFilterID = "all"
        resetDayDrawerVisibleItemLimit()
        loadDetailItemsIfNeeded(for: dayKey)
    }

    private func handleMonthPagingChanged(_ value: DragGesture.Value, width: CGFloat) {
        guard !isMonthPaging else { return }
        let horizontal = value.translation.width
        let vertical = value.translation.height
        guard abs(horizontal) > abs(vertical) else {
            monthPageDragOffset = 0
            return
        }
        monthPageDragOffset = max(-width, min(width, horizontal))
    }

    private func handleMonthPagingEnded(_ value: DragGesture.Value, width: CGFloat) {
        guard !isMonthPaging else { return }

        let horizontal = value.translation.width
        let predicted = value.predictedEndTranslation.width
        let threshold = max(56, width * 0.18)
        let decision: Int
        if horizontal <= -threshold || predicted <= -threshold * 1.25 {
            decision = 1
        } else if horizontal >= threshold || predicted >= threshold * 1.25 {
            decision = -1
        } else {
            decision = 0
        }

        guard decision != 0 else {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                monthPageDragOffset = 0
            }
            return
        }

        isMonthPaging = true
        let targetOffset = decision > 0 ? -width : width
        scheduleImmediateMonthBlockWarmup(
            anchorMonth: currentMonthCursor,
            relativeOffsets: [decision > 0 ? 2 : -2]
        )
        withAnimation(.easeOut(duration: 0.22)) {
            monthPageDragOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            let calendar = Calendar.current
            let baseMonth = startOfMonth(currentMonthCursor)
            let nextMonth = calendar.date(byAdding: .month, value: decision, to: baseMonth) ?? baseMonth
            currentMonthCursor = startOfMonth(nextMonth)
            rebuildVisibleMonthBlocks()
            scheduleMonthBlockPoolPrebuild(anchorMonth: currentMonthCursor, force: false)
            monthPageDragOffset = 0
            isMonthPaging = false
        }
    }

    private var monthListSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.82))
                        .frame(width: 128, height: 18)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                        .frame(height: 162)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private func dayDrawerLayer(proxy: GeometryProxy) -> some View {
        let width = min(proxy.size.width * 0.70, 266)
        let bucket = selectedBucket

        return ZStack {
            Button {
                closeDayDrawer()
            } label: {
                Color(red: 0.11, green: 0.23, blue: 0.29, opacity: 0.16)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 12) {
                if let bucket {
                    DayDrawerFilterRail(
                        ids: dayFilterIDs(for: bucket),
                        categories: categories,
                        counts: bucket.counts,
                        totalCount: bucket.totalCount,
                        selectedID: dayFilterID,
                        activeGradient: activeGradient,
                        activeGlowColor: activeGlowColor,
                        onSelect: { dayFilterID = $0 }
                    )
                    .padding(.top, 36)
                }

                dayDrawer(width: width)
            }
                .padding(.top, max(proxy.safeAreaInsets.top, 0) + 12)
                .padding(.trailing, 30)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 0) + 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private func dayDrawer(width: CGFloat) -> some View {
        let bucket = selectedBucket
        let filteredItems = selectedDayItems
        let renderedItems = Array(filteredItems.prefix(dayDrawerVisibleItemLimit))
        let isLoadingSelectedDayItems = selectedDayKey.map { loadingDetailDayKeys.contains($0) } ?? false

        return VStack(spacing: 10) {
            HStack {
                Text(bucket.map { L10n.Calendar.dayTitle(dayTitleOf($0.dayDate)) } ?? L10n.Calendar.dayTitleFallback)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(red: 0.21, green: 0.37, blue: 0.43))
                Spacer()
                TsugieClosePillButton(action: {
                    closeDayDrawer()
                }, accessibilityLabel: L10n.Common.close)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if bucket != nil {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(renderedItems.enumerated()), id: \.element.id) { index, item in
                                dayItemRow(item)
                                    .onAppear {
                                        loadMoreDayDrawerItemsIfNeeded(
                                            currentIndex: index,
                                            totalCount: filteredItems.count
                                        )
                                    }
                            }

                            if renderedItems.isEmpty && isLoadingSelectedDayItems {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .frame(maxWidth: .infinity, minHeight: 72)
                            } else if filteredItems.isEmpty {
                                Text(L10n.Calendar.drawerNoMatch)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        Text(L10n.Calendar.selectedDayEmpty)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.95), Color.white.opacity(0.88), Color(red: 0.94, green: 0.98, blue: 1.0, opacity: 0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.89, green: 0.96, blue: 0.98, opacity: 0.92), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.11, green: 0.30, blue: 0.38, opacity: 0.10), radius: 9, x: -1, y: 5)
    }

    private func dayFilterIDs(for bucket: CalendarBucket) -> [String] {
        ["all"] + categories
            .map(\.id)
            .filter { $0 != "all" && (bucket.counts[$0] ?? 0) > 0 }
    }

    private func dayItemRow(_ item: CalendarScoredItem) -> some View {
        let category = categories.first(where: { $0.id == item.categoryID }) ?? categories[0]
        let state = placeStateProvider(item.place.id)
        let stamp = stampProvider(item.place.id, item.place.heType)
        return Button {
            closeDayDrawer()
            onSelectPlace(item.place.id)
        } label: {
            VStack(spacing: 7) {
                HStack(alignment: .center, spacing: 9) {
                    if category.id == "hanabi" {
                        Image(category.iconName)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(hanabiCategoryGradient)
                    } else {
                        Image(category.iconName)
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.place.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                            .lineLimit(1)
                        Text(distanceLabel(item.distanceMeters))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.38, green: 0.49, blue: 0.54))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(L10n.Common.timeRange(item.snapshot.startLabel, item.snapshot.endLabel))
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.38, green: 0.49, blue: 0.54))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(item.snapshot.leftLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.31, green: 0.43, blue: 0.48))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.86)
                            .layoutPriority(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 5) {
                        HStack(spacing: 6) {
                            FavoriteStateIconView(
                                isFavorite: state.isFavorite,
                                size: 24,
                                renderMode: .lightweight
                            )
                            StampIconView(
                                stamp: stamp,
                                isColorized: state.isCheckedIn,
                                size: 25,
                                loadMode: .deferred
                            )
                        }
                    }
                }

                TsugieMiniProgressView(snapshot: item.snapshot, renderMode: .lightweight)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var hanabiCategoryGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 250.0 / 255.0, green: 112.0 / 255.0, blue: 154.0 / 255.0),
                Color(red: 254.0 / 255.0, green: 225.0 / 255.0, blue: 64.0 / 255.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var selectedBucket: CalendarBucket? {
        guard let selectedDayKey else { return nil }
        return cachedBucketsByDayKey[selectedDayKey]
    }

    private var isDayDrawerOpen: Bool {
        selectedDayKey != nil
    }

    private func closeDayDrawer() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) {
            selectedDayKey = nil
        }
        dayFilterID = "all"
        resetDayDrawerVisibleItemLimit()
    }

    private var selectedDayItems: [CalendarScoredItem] {
        guard let selectedDayKey else {
            return []
        }
        let source = cachedDetailItemsByDayKey[selectedDayKey] ?? []
        return filteredDayItems(source)
    }

    private func filteredDayItems(_ source: [CalendarScoredItem]) -> [CalendarScoredItem] {
        if dayFilterID == "all" {
            return source
        }
        return source.filter { $0.categoryID == dayFilterID }
    }

    private func resetDayDrawerVisibleItemLimit() {
        dayDrawerVisibleItemLimit = Self.dayDrawerPageSize
    }

    private func loadMoreDayDrawerItemsIfNeeded(currentIndex: Int, totalCount: Int) {
        guard totalCount > dayDrawerVisibleItemLimit else {
            return
        }
        guard currentIndex >= dayDrawerVisibleItemLimit - 4 else {
            return
        }
        dayDrawerVisibleItemLimit = min(
            totalCount,
            dayDrawerVisibleItemLimit + Self.dayDrawerPageSize
        )
    }

    private func refreshCalendarCacheIfNeeded(force: Bool) {
        let signature = makePlacesSignature()
        guard force || signature != cachedPlacesSignature else {
            return
        }
        cachedPlacesSignature = signature
        cachedDetailPlacesByDayKey = [:]
        cachedDetailItemsByDayKey = [:]
        monthBlockPool = [:]
        isMonthPaging = false
        monthPageDragOffset = 0

        calendarCacheBuildToken &+= 1
        monthBlockPoolBuildToken &+= 1
        let buildToken = calendarCacheBuildToken
        let sourcePlaces = places
        let baseDate = now
        let calendar = Calendar.current
        let locale = L10n.locale
        let requestedMonthCursor = force ? startOfMonth(baseDate) : startOfMonth(currentMonthCursor)

        if let prewarmed = Self.consumePrewarmedPayload(signature: signature, localeIdentifier: locale.identifier) {
            cachedBucketsByDayKey = prewarmed.bucketsByDayKey
            cachedDetailItemsByDayKey = [:]
            loadingDetailDayKeys = []
            if force {
                currentMonthCursor = startOfMonth(baseDate)
            }
            monthBlockPool = prewarmed.monthBlockPool
            rebuildVisibleMonthBlocks()
            scheduleMonthBlockPoolPrebuild(anchorMonth: currentMonthCursor, force: false)
            scheduleDetailPlacesPrebuild(calendar: calendar, buildToken: buildToken)
            isCalendarCacheLoading = false

            if let selectedDayKey, cachedBucketsByDayKey[selectedDayKey] == nil {
                closeDayDrawer()
            }
            return
        }
        isCalendarCacheLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            #if DEBUG
            let buildStart = Self.debugTimestamp()
            #endif
            let buckets = Self.buildCalendarBuckets(from: sourcePlaces, calendar: calendar)
            let bucketsByDayKey = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
            let visibleMonthPool = Self.buildMonthBlockPool(
                anchorMonth: requestedMonthCursor,
                offsets: -1...1,
                bucketMap: bucketsByDayKey,
                locale: locale,
                calendar: calendar
            )
            #if DEBUG
            let buildElapsed = (Self.debugTimestamp() - buildStart) * 1000
            Self.debugLog("refreshCalendarCache buckets=\(buckets.count) visibleMonths=\(visibleMonthPool.count) sourcePlaces=\(sourcePlaces.count) elapsed=\(Int(buildElapsed))ms")
            #endif

            DispatchQueue.main.async {
                guard buildToken == calendarCacheBuildToken else {
                    return
                }
                cachedBucketsByDayKey = bucketsByDayKey
                cachedDetailItemsByDayKey = [:]
                loadingDetailDayKeys = []
                if force {
                    currentMonthCursor = requestedMonthCursor
                }
                monthBlockPool = visibleMonthPool
                rebuildVisibleMonthBlocks()
                scheduleMonthBlockPoolPrebuild(anchorMonth: currentMonthCursor, force: true)
                scheduleDetailPlacesPrebuild(calendar: calendar, buildToken: buildToken)
                isCalendarCacheLoading = false

                if let selectedDayKey, cachedBucketsByDayKey[selectedDayKey] == nil {
                    closeDayDrawer()
                }
            }
        }
    }

    private func scheduleDetailPlacesPrebuild(
        calendar: Calendar,
        buildToken: Int
    ) {
        DispatchQueue.main.async {
            guard buildToken == calendarCacheBuildToken else {
                return
            }
            let sourceDetailPlaces = detailPlacesProvider()
            guard !sourceDetailPlaces.isEmpty else {
                cachedDetailPlacesByDayKey = [:]
                return
            }

            DispatchQueue.global(qos: .utility).async {
                #if DEBUG
                let groupStart = Self.debugTimestamp()
                #endif
                let grouped = Self.groupDetailPlacesByDayKey(from: sourceDetailPlaces, calendar: calendar)
                #if DEBUG
                let groupElapsed = (Self.debugTimestamp() - groupStart) * 1000
                Self.debugLog("groupDetailPlaces days=\(grouped.count) places=\(sourceDetailPlaces.count) elapsed=\(Int(groupElapsed))ms")
                #endif

                DispatchQueue.main.async {
                    guard buildToken == calendarCacheBuildToken else {
                        return
                    }
                    cachedDetailPlacesByDayKey = grouped
                }
            }
        }
    }

    private func loadDetailItemsIfNeeded(for dayKey: String) {
        if cachedDetailItemsByDayKey[dayKey] != nil || loadingDetailDayKeys.contains(dayKey) {
            return
        }

        loadingDetailDayKeys.insert(dayKey)
        let buildToken = calendarCacheBuildToken
        let referenceNow = now
        let calendar = Calendar.current

        if let groupedDetailPlaces = cachedDetailPlacesByDayKey[dayKey] {
            scheduleDetailItemsBuild(
                dayKey: dayKey,
                detailPlaces: groupedDetailPlaces,
                buildToken: buildToken,
                now: referenceNow,
                calendar: calendar
            )
            return
        }

        DispatchQueue.main.async {
            guard buildToken == calendarCacheBuildToken else {
                loadingDetailDayKeys.remove(dayKey)
                return
            }
            let sourceDetailPlaces = detailPlacesProvider()
            DispatchQueue.global(qos: .userInitiated).async {
                let dayPlaces = sourceDetailPlaces.filter { place in
                    guard let startAt = place.startAt else {
                        return false
                    }
                    return Self.calendarDayKey(startAt, calendar: calendar) == dayKey
                }

                DispatchQueue.main.async {
                    guard buildToken == calendarCacheBuildToken else {
                        loadingDetailDayKeys.remove(dayKey)
                        return
                    }
                    scheduleDetailItemsBuild(
                        dayKey: dayKey,
                        detailPlaces: dayPlaces,
                        buildToken: buildToken,
                        now: referenceNow,
                        calendar: calendar
                    )
                }
            }
        }
    }

    private func scheduleDetailItemsBuild(
        dayKey: String,
        detailPlaces: [HePlace],
        buildToken: Int,
        now: Date,
        calendar: Calendar
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            #if DEBUG
            let buildStart = Self.debugTimestamp()
            #endif
            let built = Self.buildDetailItems(
                for: dayKey,
                detailPlaces: detailPlaces,
                now: now,
                calendar: calendar
            )
            #if DEBUG
            let buildElapsed = (Self.debugTimestamp() - buildStart) * 1000
            Self.debugLog("buildDetailItems day=\(dayKey) places=\(detailPlaces.count) items=\(built.count) elapsed=\(Int(buildElapsed))ms")
            #endif

            DispatchQueue.main.async {
                guard buildToken == calendarCacheBuildToken else {
                    loadingDetailDayKeys.remove(dayKey)
                    return
                }
                cachedDetailItemsByDayKey[dayKey] = built
                loadingDetailDayKeys.remove(dayKey)
            }
        }
    }

    private func makePlacesSignature() -> String {
        Self.makePlacesSignature(places: places)
    }

    private func dayKeyOf(_ date: Date) -> String {
        let y = Calendar.current.component(.year, from: date)
        let m = Calendar.current.component(.month, from: date)
        let d = Calendar.current.component(.day, from: date)
        return "\(y)-\(String(format: "%02d", m))-\(String(format: "%02d", d))"
    }

    private func dayTitleOf(_ date: Date) -> String {
        let m = Calendar.current.component(.month, from: date)
        let d = Calendar.current.component(.day, from: date)
        let symbols = weekdaySymbolsCache.isEmpty ? Self.defaultWeekdaySymbols : weekdaySymbolsCache
        let w = symbols[(Calendar.current.component(.weekday, from: date) + 6) % symbols.count]
        return "\(m)/\(d) (\(w))"
    }

    private func distanceLabel(_ meters: Double) -> String {
        let safe = max(meters, 0)
        if safe < 1_000 {
            return "\(Int(max(80, safe.rounded())))m"
        }
        return "\((safe / 1_000).formatted(.number.locale(L10n.locale).precision(.fractionLength(1))))km"
    }

    private func startOfMonth(_ date: Date) -> Date {
        Self.startOfMonth(date, calendar: Calendar.current)
    }

    private func rebuildVisibleMonthBlocks() {
        previousMonthBlock = monthBlockForPage(offset: -1)
        currentMonthBlock = monthBlockForPage(offset: 0)
        nextMonthBlock = monthBlockForPage(offset: 1)
    }

    private func scheduleMonthBlockPoolPrebuild(anchorMonth: Date, force: Bool) {
        let calendar = Calendar.current
        let locale = L10n.locale
        let bucketMap = cachedBucketsByDayKey
        let baseMonth = startOfMonth(anchorMonth)
        let offsets = Array(-2...4)
        let targetMonths = offsets.map { calendar.date(byAdding: .month, value: $0, to: baseMonth) ?? baseMonth }
        let targetKeys = Set(targetMonths.map { Self.calendarMonthKey($0, calendar: calendar) })
        let snapshotPool = monthBlockPool
        let missingMonths = targetMonths.filter { monthStart in
            let key = Self.calendarMonthKey(monthStart, calendar: calendar)
            return snapshotPool[key] == nil
        }
        let needsPrune = snapshotPool.keys.contains { !targetKeys.contains($0) }
        guard !missingMonths.isEmpty || needsPrune else {
            return
        }

        monthBlockPoolBuildToken &+= 1
        let buildToken = monthBlockPoolBuildToken
        DispatchQueue.global(qos: .utility).async {
            #if DEBUG
            let buildStart = Self.debugTimestamp()
            #endif
            var additions: [String: CalendarMonthBlock] = [:]
            additions.reserveCapacity(missingMonths.count)
            for monthStart in missingMonths {
                let key = Self.calendarMonthKey(monthStart, calendar: calendar)
                additions[key] = Self.buildSingleCalendarMonth(
                    monthStart: monthStart,
                    bucketMap: bucketMap,
                    locale: locale,
                    calendar: calendar
                )
            }
            #if DEBUG
            let buildElapsed = (Self.debugTimestamp() - buildStart) * 1000
            Self.debugLog("scheduleMonthBlockPoolPrebuild missing=\(missingMonths.count) target=\(targetMonths.count) elapsed=\(Int(buildElapsed))ms")
            #endif

            DispatchQueue.main.async {
                guard buildToken == monthBlockPoolBuildToken else {
                    return
                }

                var nextPool = monthBlockPool
                if force || needsPrune {
                    nextPool = nextPool.filter { targetKeys.contains($0.key) }
                }
                for (key, block) in additions {
                    nextPool[key] = block
                }
                monthBlockPool = nextPool
            }
        }
    }

    private func scheduleImmediateMonthBlockWarmup(anchorMonth: Date, relativeOffsets: [Int]) {
        let calendar = Calendar.current
        let locale = L10n.locale
        let bucketMap = cachedBucketsByDayKey
        let baseMonth = startOfMonth(anchorMonth)
        let snapshotPool = monthBlockPool
        let targetMonths = relativeOffsets.map { calendar.date(byAdding: .month, value: $0, to: baseMonth) ?? baseMonth }
        let missingMonths = targetMonths.filter { monthStart in
            let key = Self.calendarMonthKey(monthStart, calendar: calendar)
            return snapshotPool[key] == nil
        }
        guard !missingMonths.isEmpty else {
            return
        }

        monthBlockPoolBuildToken &+= 1
        let buildToken = monthBlockPoolBuildToken
        DispatchQueue.global(qos: .userInitiated).async {
            #if DEBUG
            let buildStart = Self.debugTimestamp()
            #endif
            var additions: [String: CalendarMonthBlock] = [:]
            additions.reserveCapacity(missingMonths.count)
            for monthStart in missingMonths {
                let key = Self.calendarMonthKey(monthStart, calendar: calendar)
                additions[key] = Self.buildSingleCalendarMonth(
                    monthStart: monthStart,
                    bucketMap: bucketMap,
                    locale: locale,
                    calendar: calendar
                )
            }
            #if DEBUG
            let buildElapsed = (Self.debugTimestamp() - buildStart) * 1000
            Self.debugLog("scheduleImmediateMonthBlockWarmup missing=\(missingMonths.count) elapsed=\(Int(buildElapsed))ms")
            #endif

            DispatchQueue.main.async {
                guard buildToken == monthBlockPoolBuildToken else {
                    return
                }
                for (key, block) in additions {
                    monthBlockPool[key] = block
                }
            }
        }
    }

    private static func consumePrewarmedPayload(
        signature: String,
        localeIdentifier: String
    ) -> CalendarPrewarmedPayload? {
        prewarmStoreQueue.sync {
            guard let payload = prewarmedPayloadsBySignature[signature] else {
                return nil
            }
            guard payload.localeIdentifier == localeIdentifier else {
                return nil
            }
            return payload
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.78),
                    activeGlowColor.opacity(0.14),
                    Color.white.opacity(0.84)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(activeGradient)
                .opacity(0.12)

            Circle()
                .fill(activeGlowColor.opacity(0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 72)
                .offset(x: 140, y: -200)
            Circle()
                .fill(activeGradient)
                .frame(width: 260, height: 260)
                .blur(radius: 76)
                .opacity(0.14)
                .offset(x: -130, y: 120)
            Circle()
                .fill(Color.white.opacity(0.28))
                .frame(width: 220, height: 220)
                .blur(radius: 64)
                .offset(x: 40, y: 40)

            Image("HomeCalendarIcon")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 148, height: 148)
                .opacity(0.14)
                .blendMode(.multiply)
                .padding(.trailing, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

}
