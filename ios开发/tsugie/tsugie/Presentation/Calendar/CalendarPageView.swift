import SwiftUI

private struct CalendarCategoryMeta: Identifiable {
    let id: String
    let label: String
    let iconName: String
}

private struct CalendarScoredItem: Identifiable {
    let id: UUID
    let place: HePlace
    let snapshot: EventStatusSnapshot
    let distanceMeters: Double
    let categoryID: String
    let dayKey: String
}

private struct CalendarBucket: Identifiable {
    let id: String
    let dayDate: Date
    let counts: [String: Int]
    let totalCount: Int
}

private struct CalendarMonthBlock: Identifiable {
    struct Cell: Identifiable {
        let id: String
        let day: Int?
        let dayKey: String?
        let date: Date?
        let bucket: CalendarBucket?
    }

    let id: String
    let title: String
    let cells: [Cell]
}

private struct CalendarPrewarmedPayload {
    let signature: String
    let localeIdentifier: String
    let bucketsByDayKey: [String: CalendarBucket]
    let detailItemsByDayKey: [String: [CalendarScoredItem]]
    let monthBlockPool: [String: CalendarMonthBlock]
}

private struct DayDrawerFilterRail: View {
    let ids: [String]
    let categories: [CalendarCategoryMeta]
    let counts: [String: Int]
    let totalCount: Int
    let selectedID: String
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(ids, id: \.self) { id in
                let category = categories.first(where: { $0.id == id }) ?? categories[0]
                let count = id == "all" ? totalCount : (counts[id] ?? 0)
                let isActive = selectedID == id

                TsugieFilterPill(
                    leadingText: category.label,
                    leadingIconName: category.iconName,
                    trailingText: "\(count)",
                    isActive: isActive,
                    activeGradient: activeGradient,
                    activeGlowColor: activeGlowColor,
                    fixedWidth: 82,
                    fixedHeight: 32,
                    onTap: { onSelect(id) }
                )
                .accessibilityLabel("\(category.label) \(count)")
            }
        }
    }
}

struct TsugieFilterPill: View {
    let leadingText: String
    var leadingIconName: String? = nil
    let trailingText: String
    let isActive: Bool
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    var fixedWidth: CGFloat? = nil
    var fixedHeight: CGFloat = 34
    let onTap: () -> Void

    @State private var pillScale: CGFloat = 1.0
    @State private var bounceNonce: Int = 0
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            triggerJellyBounce()
            onTap()
        } label: {
            HStack(spacing: 6) {
                if let leadingIconName {
                    if leadingIconName == TsugieSmallIcon.hanabiAsset {
                        Image(leadingIconName)
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(hanabiIconGradient)
                    } else {
                        Image(leadingIconName)
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .scaleEffect(1.5)
                            .saturation(1.25)
                            .contrast(1.06)
                    }
                } else {
                    Text(leadingText)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Color(red: 0.27, green: 0.42, blue: 0.49))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Text(trailingText)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color(red: 0.30, green: 0.44, blue: 0.50))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, fixedWidth == nil ? 10 : 0)
            .padding(.vertical, fixedWidth == nil ? 4 : 0)
            .frame(width: fixedWidth)
            .frame(minHeight: fixedHeight)
            .background(Color.white, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        Color(red: 0.82, green: 0.90, blue: 0.94, opacity: 0.90),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color(red: 0.12, green: 0.30, blue: 0.38, opacity: 0.09),
                radius: 4,
                x: 0,
                y: 2
            )
            .scaleEffect(pillScale)
        }
        .buttonStyle(.plain)
        .tsugieActiveGlow(
            isActive: isActive,
            glowGradient: activeGradient,
            glowColor: activeGlowColor,
            cornerRadius: fixedHeight * 0.5,
            blurRadius: 12,
            glowOpacity: 0.68,
            scale: 1.04,
            primaryOpacity: 0.54,
            primaryRadius: 14,
            primaryYOffset: 4,
            secondaryOpacity: 0.34,
            secondaryRadius: 22,
            secondaryYOffset: 7
        )
        .opacity(isActive ? 1.0 : 0.56)
        .scaleEffect(isActive ? 1.0 : 0.97)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isActive)
    }

    private var hanabiIconGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 250.0 / 255.0, green: 112.0 / 255.0, blue: 154.0 / 255.0),
                Color(red: 254.0 / 255.0, green: 225.0 / 255.0, blue: 64.0 / 255.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func triggerJellyBounce() {
        if accessibilityReduceMotion {
            pillScale = 1.0
            return
        }

        bounceNonce += 1
        let current = bounceNonce

        withAnimation(.easeOut(duration: 0.08)) {
            pillScale = 0.90
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard current == bounceNonce else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.34)) {
                pillScale = 1.10
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard current == bounceNonce else { return }
            withAnimation(.spring(response: 0.20, dampingFraction: 0.74)) {
                pillScale = 1.0
            }
        }
    }
}

struct CalendarPageView: View {
    let places: [HePlace]
    let detailPlaces: [HePlace]
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
    private static let dayDrawerPageSize = 24

    static func prewarmCache(
        places: [HePlace],
        detailPlaces: [HePlace],
        now: Date,
        locale: Locale
    ) {
        let signature = makePlacesSignature(places: places, detailPlaces: detailPlaces)
        let calendar = Calendar.current
        let buckets = buildCalendarBuckets(from: places, calendar: calendar)
        let bucketsByDayKey = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
        let detailItemsByDayKey = buildDetailItemsByDayKey(
            from: detailPlaces,
            now: now,
            calendar: calendar
        )
        let anchorMonth = startOfMonth(now, calendar: calendar)
        let monthPool = buildMonthBlockPool(
            anchorMonth: anchorMonth,
            offsets: -4...8,
            bucketMap: bucketsByDayKey,
            locale: locale,
            calendar: calendar
        )
        let payload = CalendarPrewarmedPayload(
            signature: signature,
            localeIdentifier: locale.identifier,
            bucketsByDayKey: bucketsByDayKey,
            detailItemsByDayKey: detailItemsByDayKey,
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
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing)
                                    .combined(with: .opacity)
                                    .combined(with: .scale(scale: 0.96, anchor: .trailing)),
                                removal: .opacity
                            )
                        )
                        .zIndex(8)
                }
            }
            .ignoresSafeArea()
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isDayDrawerOpen)
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
            .onChange(of: detailPlaces.count) { _, _ in
                refreshCalendarCacheIfNeeded(force: false)
            }
            .onChange(of: selectedDayKey) { _, newDayKey in
                resetDayDrawerVisibleItemLimit()
                guard let newDayKey else {
                    return
                }
                loadDetailItemsIfNeeded(for: newDayKey)
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
                    let shouldRenderAdjacentMonths = isMonthPaging || abs(monthPageDragOffset) > 0.5
                    ZStack(alignment: .top) {
                        if shouldRenderAdjacentMonths {
                            monthBlock(previousBlock)
                                .frame(width: width)
                                .offset(x: -width + monthPageDragOffset)
                        }

                        monthBlock(currentBlock)
                            .frame(width: width)
                            .offset(x: monthPageDragOffset)

                        if shouldRenderAdjacentMonths {
                            monthBlock(nextBlock)
                                .frame(width: width)
                                .offset(x: width + monthPageDragOffset)
                        }
                    }
                    .frame(width: width)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                    .clipped()
                    .gesture(monthPagingGesture(width: width))
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

    private func monthPagingGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !isMonthPaging else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else {
                    monthPageDragOffset = 0
                    return
                }
                monthPageDragOffset = max(-width, min(width, horizontal))
            }
            .onEnded { value in
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

    private func monthBlock(_ block: CalendarMonthBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(red: 0.21, green: 0.37, blue: 0.44))
                .padding(.horizontal, 4)

            HStack(spacing: 6) {
                ForEach(Array(weekdaySymbolsCache.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(
                            index == 0
                            ? Color(red: 0.88, green: 0.48, blue: 0.53)
                            : (index == 6 ? Color(red: 0.35, green: 0.53, blue: 0.79) : Color(red: 0.42, green: 0.53, blue: 0.57))
                        )
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(block.cells) { cell in
                    if let day = cell.day, let dayKey = cell.dayKey {
                        calendarDayCell(day: day, dayKey: dayKey, date: cell.date, bucket: cell.bucket)
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.clear)
                            .frame(minHeight: 72)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func calendarDayCell(day: Int, dayKey: String, date: Date?, bucket: CalendarBucket?) -> some View {
        let isToday = dayKey == dayKeyOf(now)
        let hasEvents = bucket != nil
        let isWeekend: Int = date.map { Calendar.current.component(.weekday, from: $0) } ?? 0
        let dayColor: Color = isWeekend == 1
            ? Color(red: 0.88, green: 0.47, blue: 0.53)
            : (isWeekend == 7 ? Color(red: 0.35, green: 0.53, blue: 0.79) : Color(red: 0.24, green: 0.38, blue: 0.44))

        return Button {
            guard bucket != nil else { return }
            selectedDayKey = dayKey
            dayFilterID = "all"
            resetDayDrawerVisibleItemLimit()
        } label: {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(day)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(dayColor)

                    if let bucket {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(categories.filter { $0.id != "all" }, id: \.id) { category in
                                if let count = bucket.counts[category.id], count > 0 {
                                    HStack(spacing: 2) {
                                        if category.id == "hanabi" {
                                            Image(TsugieSmallIcon.assetName(for: category.id))
                                                .resizable()
                                                .renderingMode(.template)
                                                .scaledToFit()
                                                .frame(width: 14, height: 14)
                                                .foregroundStyle(hanabiCategoryGradient)
                                        } else {
                                            Image(TsugieSmallIcon.assetName(for: category.id))
                                                .resizable()
                                                .renderingMode(.original)
                                                .scaledToFit()
                                                .frame(width: 14, height: 14)
                                                .saturation(1.25)
                                                .contrast(1.06)
                                        }
                                        Text("\(count)")
                                            .font(.system(size: 10, weight: .heavy))
                                            .foregroundStyle(Color(red: 0.35, green: 0.47, blue: 0.53))
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                }
                            }
                        }
                    }
                }

            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .padding(.top, 6)
            .padding(.leading, 7)
            .padding(.trailing, 7)
            .padding(.bottom, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cellBackground(isToday: isToday, hasEvents: hasEvents))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        hasEvents
                        ? (isToday
                           ? Color(red: 0.72, green: 0.82, blue: 0.87, opacity: 0.98)
                           : Color(red: 0.77, green: 0.87, blue: 0.92, opacity: 0.96))
                        : .clear,
                        lineWidth: hasEvents ? (isToday ? 1.4 : 1.1) : 0
                    )
            )
            .shadow(
                color: hasEvents
                    ? Color(red: 0.13, green: 0.25, blue: 0.31, opacity: isToday ? 0.13 : 0.08)
                    : .clear,
                radius: hasEvents ? (isToday ? 8 : 4) : 0,
                x: 0,
                y: hasEvents ? (isToday ? 4 : 2) : 0
            )
            .opacity(isToday ? 1.0 : 0.62)
        }
        .buttonStyle(.plain)
        .disabled(bucket == nil)
        .id(dayKey)
    }

    private func cellBackground(isToday: Bool, hasEvents: Bool) -> some ShapeStyle {
        _ = isToday
        _ = hasEvents
        return AnyShapeStyle(Color.white)
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

                            if filteredItems.isEmpty {
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
        .shadow(color: Color(red: 0.11, green: 0.30, blue: 0.38, opacity: 0.16), radius: 16, x: -2, y: 10)
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
                            .saturation(1.25)
                            .contrast(1.06)
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
                            FavoriteStateIconView(isFavorite: state.isFavorite, size: 24)
                            StampIconView(
                                stamp: stamp,
                                isColorized: state.isCheckedIn,
                                size: 25
                            )
                        }
                    }
                }

                TsugieMiniProgressView(snapshot: item.snapshot)
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
        selectedDayKey = nil
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
        cachedDetailItemsByDayKey = [:]
        monthBlockPool = [:]
        isMonthPaging = false
        monthPageDragOffset = 0

        calendarCacheBuildToken &+= 1
        monthBlockPoolBuildToken &+= 1
        let buildToken = calendarCacheBuildToken
        let sourcePlaces = places
        let sourceDetailPlaces = detailPlaces
        let baseDate = now
        let calendar = Calendar.current
        let locale = L10n.locale

        if let prewarmed = Self.consumePrewarmedPayload(signature: signature, localeIdentifier: locale.identifier) {
            cachedBucketsByDayKey = prewarmed.bucketsByDayKey
            cachedDetailItemsByDayKey = prewarmed.detailItemsByDayKey
            if force {
                currentMonthCursor = startOfMonth(baseDate)
            }
            monthBlockPool = prewarmed.monthBlockPool
            rebuildVisibleMonthBlocks()
            scheduleMonthBlockPoolPrebuild(anchorMonth: currentMonthCursor, force: false)
            isCalendarCacheLoading = false

            if let selectedDayKey, cachedBucketsByDayKey[selectedDayKey] == nil {
                closeDayDrawer()
            }
            return
        }
        isCalendarCacheLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            let buckets = Self.buildCalendarBuckets(from: sourcePlaces, calendar: calendar)
            let bucketsByDayKey = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
            let detailItemsByDayKey = Self.buildDetailItemsByDayKey(
                from: sourceDetailPlaces,
                now: baseDate,
                calendar: calendar
            )

            DispatchQueue.main.async {
                guard buildToken == calendarCacheBuildToken else {
                    return
                }
                cachedBucketsByDayKey = bucketsByDayKey
                cachedDetailItemsByDayKey = detailItemsByDayKey
                if force {
                    currentMonthCursor = startOfMonth(baseDate)
                }
                let anchorMonth = startOfMonth(currentMonthCursor)
                monthBlockPool = Self.buildMonthBlockPool(
                    anchorMonth: anchorMonth,
                    offsets: -1...1,
                    bucketMap: bucketsByDayKey,
                    locale: locale,
                    calendar: calendar
                )
                rebuildVisibleMonthBlocks()
                scheduleMonthBlockPoolPrebuild(anchorMonth: currentMonthCursor, force: true)
                isCalendarCacheLoading = false

                if let selectedDayKey, cachedBucketsByDayKey[selectedDayKey] == nil {
                    closeDayDrawer()
                }
            }
        }
    }

    private func loadDetailItemsIfNeeded(for dayKey: String) {
        if cachedDetailItemsByDayKey[dayKey] != nil {
            return
        }

        let built = buildDetailItems(for: dayKey)
        cachedDetailItemsByDayKey[dayKey] = built
    }

    private func buildDetailItems(for dayKey: String) -> [CalendarScoredItem] {
        let items = detailPlaces.compactMap { place -> CalendarScoredItem? in
            guard let startAt = place.startAt else {
                return nil
            }
            guard dayKeyOf(startAt) == dayKey else {
                return nil
            }
            let snapshot = EventStatusResolver.snapshot(startAt: place.startAt, endAt: place.endAt, now: now)
            return CalendarScoredItem(
                id: place.id,
                place: place,
                snapshot: snapshot,
                distanceMeters: place.distanceMeters,
                categoryID: categoryID(for: place),
                dayKey: dayKey
            )
        }
        return items.sorted(by: recommendationCompare)
    }

    private static func buildDetailItemsByDayKey(
        from sourcePlaces: [HePlace],
        now: Date,
        calendar: Calendar
    ) -> [String: [CalendarScoredItem]] {
        var grouped: [String: [CalendarScoredItem]] = [:]
        grouped.reserveCapacity(max(sourcePlaces.count / 3, 8))

        for place in sourcePlaces {
            guard let startAt = place.startAt else {
                continue
            }
            let dayKey = calendarDayKey(startAt, calendar: calendar)
            let snapshot = EventStatusResolver.snapshot(startAt: place.startAt, endAt: place.endAt, now: now)
            let item = CalendarScoredItem(
                id: place.id,
                place: place,
                snapshot: snapshot,
                distanceMeters: place.distanceMeters,
                categoryID: calendarCategoryID(for: place),
                dayKey: dayKey
            )
            grouped[dayKey, default: []].append(item)
        }

        for key in grouped.keys {
            grouped[key]?.sort(by: recommendationCompareStatic)
        }
        return grouped
    }

    private static func buildCalendarBuckets(from sourcePlaces: [HePlace], calendar: Calendar) -> [CalendarBucket] {
        var countsByDay: [String: [String: Int]] = [:]
        var dateByDay: [String: Date] = [:]

        for place in sourcePlaces {
            guard let start = place.startAt else {
                continue
            }
            let key = calendarDayKey(start, calendar: calendar)
            let normalizedDate = calendar.startOfDay(for: start)
            dateByDay[key] = dateByDay[key] ?? normalizedDate
            let category = calendarCategoryID(for: place)
            var counts = countsByDay[key, default: [:]]
            counts[category, default: 0] += 1
            countsByDay[key] = counts
        }

        var buckets: [CalendarBucket] = countsByDay.compactMap { key, counts in
            guard let date = dateByDay[key] else { return nil }
            let totalCount = counts.values.reduce(0, +)
            return CalendarBucket(id: key, dayDate: date, counts: counts, totalCount: totalCount)
        }
        buckets.sort { $0.dayDate < $1.dayDate }
        return buckets
    }

    private static func buildCalendarMonths(
        from buckets: [CalendarBucket],
        now: Date,
        locale: Locale,
        calendar: Calendar
    ) -> [CalendarMonthBlock] {
        guard !buckets.isEmpty else { return [] }

        let bucketMap = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
        let firstDate = buckets.first?.dayDate ?? now
        let lastDate = buckets.last?.dayDate ?? now
        let currentMonth = DateComponents(calendar: calendar, year: calendar.component(.year, from: now), month: calendar.component(.month, from: now), day: 1).date ?? now
        let firstMonth = DateComponents(calendar: calendar, year: calendar.component(.year, from: firstDate), month: calendar.component(.month, from: firstDate), day: 1).date ?? now
        let lastMonth = DateComponents(calendar: calendar, year: calendar.component(.year, from: lastDate), month: calendar.component(.month, from: lastDate), day: 1).date ?? now
        let baselineStart = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        let baselineEnd = calendar.date(byAdding: .month, value: 5, to: currentMonth) ?? currentMonth
        let start = min(firstMonth, min(currentMonth, baselineStart))
        let end = max(lastMonth, max(currentMonth, baselineEnd))

        var blocks: [CalendarMonthBlock] = []
        var cursor = start
        while cursor <= end {
            let year = calendar.component(.year, from: cursor)
            let month = calendar.component(.month, from: cursor)
            let firstWeekday = calendar.component(.weekday, from: cursor) - 1
            let daysInMonth = calendar.range(of: .day, in: .month, for: cursor)?.count ?? 30
            var cells: [CalendarMonthBlock.Cell] = []
            let monthID = "\(year)-\(String(format: "%02d", month))"

            for _ in 0..<firstWeekday {
                let fillerIndex = cells.count
                cells.append(
                    .init(
                        id: "\(monthID)-pad-\(fillerIndex)",
                        day: nil,
                        dayKey: nil,
                        date: nil,
                        bucket: nil
                    )
                )
            }

            for day in 1...daysInMonth {
                let date = DateComponents(calendar: calendar, year: year, month: month, day: day).date
                let key = date.map { calendarDayKey($0, calendar: calendar) } ?? ""
                let cellID = key.isEmpty ? "\(monthID)-day-\(day)" : key
                cells.append(
                    .init(
                        id: cellID,
                        day: day,
                        dayKey: key,
                        date: date,
                        bucket: bucketMap[key]
                    )
                )
            }

            blocks.append(
                CalendarMonthBlock(
                    id: monthID,
                    title: cursor.formatted(
                        Date.FormatStyle()
                            .year(.defaultDigits)
                            .month(.wide)
                            .locale(locale)
                    ),
                    cells: cells
                )
            )

            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }

        return blocks
    }

    private static func calendarCategoryID(for place: HePlace) -> String {
        switch place.heType {
        case .hanabi: return "hanabi"
        case .matsuri: return "matsuri"
        case .nature: return "nature"
        case .other: return "other"
        }
    }

    private static func calendarDayKey(_ date: Date, calendar: Calendar) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "\(y)-\(String(format: "%02d", m))-\(String(format: "%02d", d))"
    }

    private static func makePlacesSignature(places: [HePlace], detailPlaces: [HePlace]) -> String {
        let placesFirst = places.first?.id.uuidString ?? "nil"
        let placesLast = places.last?.id.uuidString ?? "nil"
        let detailFirst = detailPlaces.first?.id.uuidString ?? "nil"
        let detailLast = detailPlaces.last?.id.uuidString ?? "nil"
        return "\(places.count)|\(placesFirst)|\(placesLast)|\(detailPlaces.count)|\(detailFirst)|\(detailLast)"
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func makePlacesSignature() -> String {
        Self.makePlacesSignature(places: places, detailPlaces: detailPlaces)
    }

    private func categoryID(for place: HePlace) -> String {
        switch place.heType {
        case .hanabi: return "hanabi"
        case .matsuri: return "matsuri"
        case .nature: return "nature"
        case .other: return "other"
        }
    }

    private func recommendationCompare(_ lhs: CalendarScoredItem, _ rhs: CalendarScoredItem) -> Bool {
        Self.recommendationCompareStatic(lhs, rhs)
    }

    nonisolated private static func recommendationCompareStatic(_ lhs: CalendarScoredItem, _ rhs: CalendarScoredItem) -> Bool {
        let lhsOngoing = lhs.snapshot.status == .ongoing
        let rhsOngoing = rhs.snapshot.status == .ongoing
        if lhsOngoing != rhsOngoing {
            return lhsOngoing
        }
        if lhs.distanceMeters != rhs.distanceMeters {
            return lhs.distanceMeters < rhs.distanceMeters
        }
        let lStart = lhs.snapshot.startDate?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
        let rStart = rhs.snapshot.startDate?.timeIntervalSince1970 ?? .greatestFiniteMagnitude
        if lStart != rStart {
            return lStart < rStart
        }
        return lhs.place.heatScore > rhs.place.heatScore
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
        let offsets = Array(-4...8)
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

    private static func buildSingleCalendarMonth(
        monthStart: Date,
        bucketMap: [String: CalendarBucket],
        locale: Locale,
        calendar: Calendar
    ) -> CalendarMonthBlock {
        let year = calendar.component(.year, from: monthStart)
        let month = calendar.component(.month, from: monthStart)
        let monthID = "\(year)-\(String(format: "%02d", month))"
        let firstWeekday = calendar.component(.weekday, from: monthStart) - 1
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        var cells: [CalendarMonthBlock.Cell] = []
        cells.reserveCapacity(daysInMonth + 12)

        if firstWeekday > 0 {
            for index in 0..<firstWeekday {
                cells.append(
                    .init(
                        id: "\(monthID)-pad-\(index)",
                        day: nil,
                        dayKey: nil,
                        date: nil,
                        bucket: nil
                    )
                )
            }
        }

        for day in 1...daysInMonth {
            let date = DateComponents(calendar: calendar, year: year, month: month, day: day).date
            let key = date.map { calendarDayKey($0, calendar: calendar) } ?? ""
            let cellID = key.isEmpty ? "\(monthID)-day-\(day)" : key
            cells.append(
                .init(
                    id: cellID,
                    day: day,
                    dayKey: key,
                    date: date,
                    bucket: bucketMap[key]
                )
            )
        }

        let trailingPadCount = (7 - (cells.count % 7)) % 7
        if trailingPadCount > 0 {
            for index in 0..<trailingPadCount {
                cells.append(
                    .init(
                        id: "\(monthID)-tail-\(index)",
                        day: nil,
                        dayKey: nil,
                        date: nil,
                        bucket: nil
                    )
                )
            }
        }

        return CalendarMonthBlock(
            id: monthID,
            title: monthStart.formatted(
                Date.FormatStyle()
                    .year(.defaultDigits)
                    .month(.wide)
                    .locale(locale)
            ),
            cells: cells
        )
    }

    private static func calendarMonthKey(_ date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "\(year)-\(String(format: "%02d", month))"
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

    private static func buildMonthBlockPool(
        anchorMonth: Date,
        offsets: ClosedRange<Int>,
        bucketMap: [String: CalendarBucket],
        locale: Locale,
        calendar: Calendar
    ) -> [String: CalendarMonthBlock] {
        var pool: [String: CalendarMonthBlock] = [:]
        pool.reserveCapacity(offsets.count)
        for offset in offsets {
            let monthStart = calendar.date(byAdding: .month, value: offset, to: anchorMonth) ?? anchorMonth
            let key = calendarMonthKey(monthStart, calendar: calendar)
            pool[key] = buildSingleCalendarMonth(
                monthStart: monthStart,
                bucketMap: bucketMap,
                locale: locale,
                calendar: calendar
            )
        }
        return pool
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.62),
                    activeGlowColor.opacity(0.32),
                    Color.white.opacity(0.72),
                    activeGlowColor.opacity(0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(activeGradient)
                .opacity(0.26)
                .blendMode(.overlay)
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.46)

            Circle()
                .fill(activeGlowColor.opacity(0.36))
                .frame(width: 420, height: 420)
                .blur(radius: 118)
                .offset(x: 150, y: -220)
            Circle()
                .fill(activeGlowColor.opacity(0.28))
                .frame(width: 360, height: 360)
                .blur(radius: 104)
                .offset(x: -180, y: 180)
            Circle()
                .fill(activeGradient)
                .frame(width: 360, height: 360)
                .blur(radius: 122)
                .opacity(0.22)
                .offset(x: 110, y: -80)
            Circle()
                .fill(activeGradient)
                .frame(width: 300, height: 300)
                .blur(radius: 108)
                .opacity(0.18)
                .offset(x: -150, y: 140)

            Image("HomeCalendarIcon")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 168, height: 168)
                .opacity(0.22)
                .blendMode(.multiply)
                .padding(.trailing, 18)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private static var defaultWeekdaySymbols: [String] {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    private static func buildWeekdaySymbols(locale: Locale) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar.current
        let symbols = formatter.shortWeekdaySymbols ?? defaultWeekdaySymbols
        if symbols.count == 7 {
            return symbols.indices.map { symbols[($0 + 1) % 7] }
        }
        return defaultWeekdaySymbols
    }
}
