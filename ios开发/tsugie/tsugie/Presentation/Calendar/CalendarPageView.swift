import QuartzCore
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

private struct CalendarBucket: Identifiable, Equatable {
    let id: String
    let dayDate: Date
    let counts: [String: Int]
    let totalCount: Int
}

private struct CalendarMonthBlock: Identifiable, Equatable {
    struct Cell: Identifiable, Equatable {
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

private let calendarDayCellCategoryIDs = ["hanabi", "matsuri", "nature", "other"]

private struct CalendarPrewarmedPayload {
    let signature: String
    let localeIdentifier: String
    let bucketsByDayKey: [String: CalendarBucket]
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
                    renderMode: .lightweight,
                    onTap: { onSelect(id) }
                )
                .accessibilityLabel("\(category.label) \(count)")
            }
        }
    }
}

enum TsugieFilterPillRenderMode {
    case standard
    case lightweight
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
    var renderMode: TsugieFilterPillRenderMode = .standard
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
                            .saturation(renderMode == .standard ? 1.25 : 1.0)
                            .contrast(renderMode == .standard ? 1.06 : 1.0)
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
            .background(pillBackground, in: Capsule())
            .overlay(
                Group {
                    if renderMode == .standard || !isActive {
                        Capsule()
                            .stroke(
                                Color(red: 0.82, green: 0.90, blue: 0.94, opacity: 0.90),
                                lineWidth: 1
                            )
                    }
                }
            )
            .shadow(
                color: Color(
                    red: 0.12,
                    green: 0.30,
                    blue: 0.38,
                    opacity: renderMode == .standard ? 0.09 : 0.04
                ),
                radius: renderMode == .standard ? 4 : 2,
                x: 0,
                y: renderMode == .standard ? 2 : 1
            )
            .scaleEffect(pillScale)
        }
        .buttonStyle(.plain)
        .modifier(
            TsugieFilterPillGlowModifier(
                isEnabled: renderMode == .standard,
                isActive: isActive,
                activeGradient: activeGradient,
                activeGlowColor: activeGlowColor,
                fixedHeight: fixedHeight
            )
        )
        .opacity(isActive ? 1.0 : 0.56)
        .scaleEffect(isActive ? 1.0 : 0.97)
        .animation(
            renderMode == .standard ? .spring(response: 0.24, dampingFraction: 0.78) : nil,
            value: isActive
        )
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
        if accessibilityReduceMotion || renderMode == .lightweight {
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

    private var pillBackground: AnyShapeStyle {
        return AnyShapeStyle(Color.white)
    }
}

private struct TsugieFilterPillGlowModifier: ViewModifier {
    let isEnabled: Bool
    let isActive: Bool
    let activeGradient: LinearGradient
    let activeGlowColor: Color
    let fixedHeight: CGFloat

    func body(content: Content) -> some View {
        if isEnabled {
            content.tsugieActiveGlow(
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
        } else if isActive {
            content
                .shadow(
                    color: activeGlowColor.opacity(0.18),
                    radius: 10,
                    x: 0,
                    y: 3
                )
                .shadow(
                    color: activeGlowColor.opacity(0.10),
                    radius: 18,
                    x: 0,
                    y: 6
                )
        } else {
            content
        }
    }
}

private struct CalendarMonthPagerView: View, Equatable {
    let width: CGFloat
    let previousBlock: CalendarMonthBlock
    let currentBlock: CalendarMonthBlock
    let nextBlock: CalendarMonthBlock
    let weekdaySymbols: [String]
    let monthPageDragOffset: CGFloat
    let isMonthPaging: Bool
    let todayDayKey: String
    let onSelectDay: (String) -> Void
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void

    static func == (lhs: CalendarMonthPagerView, rhs: CalendarMonthPagerView) -> Bool {
        lhs.width == rhs.width &&
        lhs.previousBlock == rhs.previousBlock &&
        lhs.currentBlock == rhs.currentBlock &&
        lhs.nextBlock == rhs.nextBlock &&
        lhs.weekdaySymbols == rhs.weekdaySymbols &&
        lhs.monthPageDragOffset == rhs.monthPageDragOffset &&
        lhs.isMonthPaging == rhs.isMonthPaging &&
        lhs.todayDayKey == rhs.todayDayKey
    }

    var body: some View {
        let shouldRenderAdjacentMonths = isMonthPaging || abs(monthPageDragOffset) > 0.5

        ZStack(alignment: .top) {
            if shouldRenderAdjacentMonths {
                CalendarMonthBlockView(
                    block: previousBlock,
                    weekdaySymbols: weekdaySymbols,
                    todayDayKey: todayDayKey,
                    onSelectDay: onSelectDay
                )
                .frame(width: width)
                .offset(x: -width + monthPageDragOffset)
            }

            CalendarMonthBlockView(
                block: currentBlock,
                weekdaySymbols: weekdaySymbols,
                todayDayKey: todayDayKey,
                onSelectDay: onSelectDay
            )
            .frame(width: width)
            .offset(x: monthPageDragOffset)

            if shouldRenderAdjacentMonths {
                CalendarMonthBlockView(
                    block: nextBlock,
                    weekdaySymbols: weekdaySymbols,
                    todayDayKey: todayDayKey,
                    onSelectDay: onSelectDay
                )
                .frame(width: width)
                .offset(x: width + monthPageDragOffset)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .clipped()
        .gesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .local)
                .onChanged(onDragChanged)
                .onEnded(onDragEnded)
        )
    }
}

private struct CalendarMonthBlockView: View, Equatable {
    let block: CalendarMonthBlock
    let weekdaySymbols: [String]
    let todayDayKey: String
    let onSelectDay: (String) -> Void

    static func == (lhs: CalendarMonthBlockView, rhs: CalendarMonthBlockView) -> Bool {
        lhs.block == rhs.block &&
        lhs.weekdaySymbols == rhs.weekdaySymbols &&
        lhs.todayDayKey == rhs.todayDayKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(red: 0.21, green: 0.37, blue: 0.44))
                .padding(.horizontal, 4)

            HStack(spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, label in
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
                    CalendarDayCellView(
                        cell: cell,
                        todayDayKey: todayDayKey,
                        onSelectDay: onSelectDay
                    )
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
}

private struct CalendarDayCellView: View, Equatable {
    let cell: CalendarMonthBlock.Cell
    let todayDayKey: String
    let onSelectDay: (String) -> Void

    static func == (lhs: CalendarDayCellView, rhs: CalendarDayCellView) -> Bool {
        lhs.cell == rhs.cell && lhs.todayDayKey == rhs.todayDayKey
    }

    var body: some View {
        if let day = cell.day, let dayKey = cell.dayKey {
            let isToday = dayKey == todayDayKey
            let isWeekend = cell.date.map { Calendar.current.component(.weekday, from: $0) } ?? 0
            let dayColor: Color = isWeekend == 1
                ? Color(red: 0.88, green: 0.47, blue: 0.53)
                : (isWeekend == 7 ? Color(red: 0.35, green: 0.53, blue: 0.79) : Color(red: 0.24, green: 0.38, blue: 0.44))
            let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

            Button {
                guard cell.bucket != nil else { return }
                onSelectDay(dayKey)
            } label: {
                if let bucket = cell.bucket {
                    ZStack(alignment: .bottomTrailing) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(day)")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(dayColor)

                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(calendarDayCellCategoryIDs, id: \.self) { categoryID in
                                    if let count = bucket.counts[categoryID], count > 0 {
                                        HStack(spacing: 2) {
                                            if categoryID == "hanabi" {
                                                Image(TsugieSmallIcon.assetName(for: categoryID))
                                                    .resizable()
                                                    .renderingMode(.template)
                                                    .scaledToFit()
                                                    .frame(width: 14, height: 14)
                                                    .foregroundStyle(Self.hanabiCategoryGradient)
                                            } else {
                                                Image(TsugieSmallIcon.assetName(for: categoryID))
                                                    .resizable()
                                                    .renderingMode(.original)
                                                    .scaledToFit()
                                                    .frame(width: 14, height: 14)
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
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                    .padding(.top, 6)
                    .padding(.leading, 7)
                    .padding(.trailing, 7)
                    .padding(.bottom, 6)
                    .background(shape.fill(Color.white))
                    .overlay(
                        Group {
                            if isToday {
                                shape
                                    .stroke(
                                        Color(red: 0.72, green: 0.82, blue: 0.87, opacity: 0.98),
                                        lineWidth: 1.4
                                    )
                            }
                        }
                    )
                    .shadow(
                        color: isToday ? Color(red: 0.13, green: 0.25, blue: 0.31, opacity: 0.13) : .clear,
                        radius: isToday ? 8 : 0,
                        x: 0,
                        y: isToday ? 4 : 0
                    )
                    .opacity(isToday ? 1.0 : 0.62)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(day)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(dayColor)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                    .padding(.top, 6)
                    .padding(.leading, 7)
                    .padding(.trailing, 7)
                    .padding(.bottom, 6)
                    .background(shape.fill(Color.white.opacity(0.92)))
                    .opacity(isToday ? 1.0 : 0.62)
                }
            }
            .buttonStyle(.plain)
            .disabled(cell.bucket == nil)
            .id(dayKey)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.clear)
                .frame(minHeight: 72)
        }
    }

    private static var hanabiCategoryGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 250.0 / 255.0, green: 112.0 / 255.0, blue: 154.0 / 255.0),
                Color(red: 254.0 / 255.0, green: 225.0 / 255.0, blue: 64.0 / 255.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

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

    private func monthPagingGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                handleMonthPagingChanged(value, width: width)
            }
            .onEnded { value in
                handleMonthPagingEnded(value, width: width)
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
        let isWeekend: Int = date.map { Calendar.current.component(.weekday, from: $0) } ?? 0
        let dayColor: Color = isWeekend == 1
            ? Color(red: 0.88, green: 0.47, blue: 0.53)
            : (isWeekend == 7 ? Color(red: 0.35, green: 0.53, blue: 0.79) : Color(red: 0.24, green: 0.38, blue: 0.44))

        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return Button {
            guard bucket != nil else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                selectedDayKey = dayKey
            }
            dayFilterID = "all"
            resetDayDrawerVisibleItemLimit()
            loadDetailItemsIfNeeded(for: dayKey)
        } label: {
            if let bucket {
                ZStack(alignment: .bottomTrailing) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(day)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(dayColor)

                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Self.dayCellCategoryIDs, id: \.self) { categoryID in
                                let category = categoryMeta(for: categoryID)
                                if let count = bucket.counts[category.id], count > 0 {
                                    HStack(spacing: 2) {
                                        if category.id == "hanabi" {
                                            Image(category.iconName)
                                                .resizable()
                                                .renderingMode(.template)
                                                .scaledToFit()
                                                .frame(width: 14, height: 14)
                                                .foregroundStyle(hanabiCategoryGradient)
                                        } else {
                                            Image(category.iconName)
                                                .resizable()
                                                .renderingMode(.original)
                                                .scaledToFit()
                                                .frame(width: 14, height: 14)
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
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                .padding(.top, 6)
                .padding(.leading, 7)
                .padding(.trailing, 7)
                .padding(.bottom, 6)
                .background(
                    shape
                        .fill(cellBackground(isToday: isToday, hasEvents: true))
                )
                .overlay(
                    Group {
                        if isToday {
                            shape
                                .stroke(
                                    Color(red: 0.72, green: 0.82, blue: 0.87, opacity: 0.98),
                                    lineWidth: 1.4
                                )
                        }
                    }
                )
                .shadow(
                    color: isToday ? Color(red: 0.13, green: 0.25, blue: 0.31, opacity: 0.13) : .clear,
                    radius: isToday ? 8 : 0,
                    x: 0,
                    y: isToday ? 4 : 0
                )
                .opacity(isToday ? 1.0 : 0.62)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(day)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(dayColor)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                .padding(.top, 6)
                .padding(.leading, 7)
                .padding(.trailing, 7)
                .padding(.bottom, 6)
                .background(shape.fill(Color.white.opacity(0.92)))
                .opacity(isToday ? 1.0 : 0.62)
            }
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

    private static func buildDetailItems(
        for dayKey: String,
        detailPlaces: [HePlace],
        now: Date,
        calendar: Calendar
    ) -> [CalendarScoredItem] {
        let items = detailPlaces.compactMap { place -> CalendarScoredItem? in
            guard let startAt = place.startAt else {
                return nil
            }
            guard calendarDayKey(startAt, calendar: calendar) == dayKey else {
                return nil
            }
            let snapshot = EventStatusResolver.snapshot(startAt: place.startAt, endAt: place.endAt, now: now)
            return CalendarScoredItem(
                id: place.id,
                place: place,
                snapshot: snapshot,
                distanceMeters: place.distanceMeters,
                categoryID: calendarCategoryID(for: place),
                dayKey: dayKey
            )
        }
        return items.sorted(by: recommendationCompareStatic)
    }

    private static func groupDetailPlacesByDayKey(
        from sourcePlaces: [HePlace],
        calendar: Calendar
    ) -> [String: [HePlace]] {
        var grouped: [String: [HePlace]] = [:]
        grouped.reserveCapacity(max(sourcePlaces.count / 3, 8))

        for place in sourcePlaces {
            guard let startAt = place.startAt else {
                continue
            }
            let dayKey = calendarDayKey(startAt, calendar: calendar)
            grouped[dayKey, default: []].append(place)
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
            let firstWeekday = weekdayColumnIndex(for: cursor, calendar: calendar)
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

    private static func makePlacesSignature(places: [HePlace]) -> String {
        let placesFirst = places.first?.id.uuidString ?? "nil"
        let placesLast = places.last?.id.uuidString ?? "nil"
        return "\(places.count)|\(placesFirst)|\(placesLast)"
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func makePlacesSignature() -> String {
        Self.makePlacesSignature(places: places)
    }

    private func categoryID(for place: HePlace) -> String {
        switch place.heType {
        case .hanabi: return "hanabi"
        case .matsuri: return "matsuri"
        case .nature: return "nature"
        case .other: return "other"
        }
    }

    private func categoryMeta(for categoryID: String) -> CalendarCategoryMeta {
        categories.first(where: { $0.id == categoryID }) ?? categories[0]
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

    private static func buildSingleCalendarMonth(
        monthStart: Date,
        bucketMap: [String: CalendarBucket],
        locale: Locale,
        calendar: Calendar
    ) -> CalendarMonthBlock {
        let year = calendar.component(.year, from: monthStart)
        let month = calendar.component(.month, from: monthStart)
        let monthID = "\(year)-\(String(format: "%02d", month))"
        let firstWeekday = weekdayColumnIndex(for: monthStart, calendar: calendar)
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

    private static func weekdayColumnIndex(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private static let dayCellCategoryIDs = ["hanabi", "matsuri", "nature", "other"]

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
