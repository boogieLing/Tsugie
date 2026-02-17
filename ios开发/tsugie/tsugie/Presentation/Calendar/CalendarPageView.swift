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
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color(red: 0.27, green: 0.42, blue: 0.49))
                }

                Text(trailingText)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color(red: 0.30, green: 0.44, blue: 0.50))
            }
            .padding(.horizontal, fixedWidth == nil ? 10 : 0)
            .frame(width: fixedWidth, height: fixedHeight)
            .frame(height: fixedHeight)
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

    @State private var selectedDayKey: String?
    @State private var dayFilterID = "all"
    @State private var didInitialAutoScroll = false
    @State private var cachedBucketsByDayKey: [String: CalendarBucket] = [:]
    @State private var cachedMonthBlocks: [CalendarMonthBlock] = []
    @State private var cachedDayKeys: Set<String> = []
    @State private var cachedDetailItemsByDayKey: [String: [CalendarScoredItem]] = [:]
    @State private var cachedPlacesSignature = ""

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
                refreshCalendarCacheIfNeeded(force: true)
            }
            .onChange(of: places.count) { _, _ in
                refreshCalendarCacheIfNeeded(force: false)
            }
            .onChange(of: detailPlaces.count) { _, _ in
                refreshCalendarCacheIfNeeded(force: false)
            }
            .onChange(of: selectedDayKey) { _, newDayKey in
                guard let newDayKey else {
                    return
                }
                loadDetailItemsIfNeeded(for: newDayKey)
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
        let blocks = cachedMonthBlocks
        let dayKeys = cachedDayKeys

        return ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 8) {
                    if blocks.isEmpty {
                        Text(L10n.Calendar.empty)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.38, green: 0.50, blue: 0.54))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    } else {
                        ForEach(blocks) { block in
                            monthBlock(block)
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scrollCurrentDayToCenterIfNeeded(scrollProxy: scrollProxy, dayKeys: dayKeys)
            }
            .onChange(of: places.count) { _, _ in
                scrollCurrentDayToCenterIfNeeded(scrollProxy: scrollProxy, dayKeys: dayKeys)
            }
            .onChange(of: cachedMonthBlocks.count) { _, _ in
                scrollCurrentDayToCenterIfNeeded(scrollProxy: scrollProxy, dayKeys: dayKeys)
            }
        }
    }

    private func monthBlock(_ block: CalendarMonthBlock) -> some View {
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
        let dayColor: Color = isWeekend == 1 ? Color(red: 0.88, green: 0.47, blue: 0.53) : (isWeekend == 7 ? Color(red: 0.35, green: 0.53, blue: 0.79) : Color(red: 0.24, green: 0.38, blue: 0.44))

        return Button {
            guard bucket != nil else { return }
            selectedDayKey = dayKey
            dayFilterID = "all"
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
                    .overlay {
                        if isToday {
                            ImmediateStampImageView(resourceName: "tsugie-logo-anime.png", maxPixelSize: 256)
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .opacity(0.26)
                                .clipped()
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        hasEvents
                        ? (isToday
                           ? activeGlowColor.opacity(0.46)
                           : Color(red: 0.77, green: 0.87, blue: 0.92, opacity: 0.96))
                        : .clear,
                        lineWidth: hasEvents ? (isToday ? 1.4 : 1.1) : 0
                    )
            )
            .shadow(
                color: hasEvents ? activeGlowColor.opacity(isToday ? 0.22 : 0.10) : .clear,
                radius: hasEvents ? (isToday ? 8 : 4) : 0,
                x: 0,
                y: hasEvents ? (isToday ? 4 : 2) : 0
            )
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
                VStack(alignment: .leading, spacing: 10) {
                    if let bucket {
                        VStack(spacing: 8) {
                            ForEach(filteredItems, id: \.id) { item in
                                dayItemRow(item)
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
            onClose()
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
        cachedDetailItemsByDayKey.removeAll(keepingCapacity: true)
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

    private func buildCalendarBuckets() -> [CalendarBucket] {
        var countsByDay: [String: [String: Int]] = [:]
        var dateByDay: [String: Date] = [:]

        for place in places {
            guard let start = place.startAt else {
                continue
            }
            let key = dayKeyOf(start)
            let normalizedDate = Calendar.current.startOfDay(for: start)
            dateByDay[key] = dateByDay[key] ?? normalizedDate
            let category = categoryID(for: place)
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

    private func refreshCalendarCacheIfNeeded(force: Bool) {
        let signature = makePlacesSignature()
        guard force || signature != cachedPlacesSignature else {
            return
        }

        let buckets = buildCalendarBuckets()
        let blocks = buildCalendarMonths(from: buckets)
        cachedBucketsByDayKey = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
        cachedMonthBlocks = blocks
        cachedDayKeys = Set(blocks.flatMap { $0.cells.compactMap(\.dayKey) })
        cachedDetailItemsByDayKey = [:]
        cachedPlacesSignature = signature

        if let selectedDayKey, cachedBucketsByDayKey[selectedDayKey] == nil {
            closeDayDrawer()
        }
    }

    private func loadDetailItemsIfNeeded(for dayKey: String) {
        if cachedDetailItemsByDayKey[dayKey] != nil {
            return
        }

        let built = buildDetailItems(for: dayKey)
        if cachedDetailItemsByDayKey.count >= 8 {
            cachedDetailItemsByDayKey.removeAll(keepingCapacity: true)
        }
        cachedDetailItemsByDayKey[dayKey] = built
    }

    private func buildDetailItems(for dayKey: String) -> [CalendarScoredItem] {
        let items = detailPlaces.compactMap { place -> CalendarScoredItem? in
            guard let start = place.startAt else {
                return nil
            }
            let key = dayKeyOf(start)
            guard key == dayKey else {
                return nil
            }
            let snapshot = EventStatusResolver.snapshot(startAt: place.startAt, endAt: place.endAt, now: now)
            return CalendarScoredItem(
                id: place.id,
                place: place,
                snapshot: snapshot,
                distanceMeters: place.distanceMeters,
                categoryID: categoryID(for: place),
                dayKey: key
            )
        }
        return items.sorted(by: recommendationCompare)
    }

    private func buildCalendarMonths(from buckets: [CalendarBucket]) -> [CalendarMonthBlock] {
        guard !buckets.isEmpty else { return [] }

        let bucketMap = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0) })
        let firstDate = buckets.first?.dayDate ?? now
        let lastDate = buckets.last?.dayDate ?? now
        let currentMonth = DateComponents(calendar: .current, year: Calendar.current.component(.year, from: now), month: Calendar.current.component(.month, from: now), day: 1).date ?? now
        let firstMonth = DateComponents(calendar: .current, year: Calendar.current.component(.year, from: firstDate), month: Calendar.current.component(.month, from: firstDate), day: 1).date ?? now
        let lastMonth = DateComponents(calendar: .current, year: Calendar.current.component(.year, from: lastDate), month: Calendar.current.component(.month, from: lastDate), day: 1).date ?? now
        let baselineStart = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
        let baselineEnd = Calendar.current.date(byAdding: .month, value: 5, to: currentMonth) ?? currentMonth
        let start = min(firstMonth, min(currentMonth, baselineStart))
        let end = max(lastMonth, max(currentMonth, baselineEnd))

        var blocks: [CalendarMonthBlock] = []
        var cursor = start
        while cursor <= end {
            let year = Calendar.current.component(.year, from: cursor)
            let month = Calendar.current.component(.month, from: cursor)
            let firstWeekday = Calendar.current.component(.weekday, from: cursor) - 1
            let daysInMonth = Calendar.current.range(of: .day, in: .month, for: cursor)?.count ?? 30
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
                let date = DateComponents(calendar: .current, year: year, month: month, day: day).date
                let key = date.map(dayKeyOf) ?? ""
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
                            .locale(L10n.locale)
                    ),
                    cells: cells
                )
            )

            cursor = Calendar.current.date(byAdding: .month, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }

        return blocks
    }

    private func makePlacesSignature() -> String {
        let placesFirst = places.first?.id.uuidString ?? "nil"
        let placesLast = places.last?.id.uuidString ?? "nil"
        let detailFirst = detailPlaces.first?.id.uuidString ?? "nil"
        let detailLast = detailPlaces.last?.id.uuidString ?? "nil"
        return "\(places.count)|\(placesFirst)|\(placesLast)|\(detailPlaces.count)|\(detailFirst)|\(detailLast)"
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
        let w = weekdaySymbols[(Calendar.current.component(.weekday, from: date) + 6) % 7]
        return "\(m)/\(d) (\(w))"
    }

    private func distanceLabel(_ meters: Double) -> String {
        let safe = max(meters, 0)
        if safe < 1_000 {
            return "\(Int(max(80, safe.rounded())))m"
        }
        return "\((safe / 1_000).formatted(.number.locale(L10n.locale).precision(.fractionLength(1))))km"
    }

    private func scrollCurrentDayToCenterIfNeeded(
        scrollProxy: ScrollViewProxy,
        dayKeys: Set<String>
    ) {
        guard !didInitialAutoScroll else { return }
        let todayKey = dayKeyOf(now)
        guard dayKeys.contains(todayKey) else { return }

        didInitialAutoScroll = true
        DispatchQueue.main.async {
            scrollProxy.scrollTo(todayKey, anchor: .center)
        }
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

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.calendar = Calendar.current
        let symbols = formatter.shortWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if symbols.count == 7 {
            return symbols.indices.map { symbols[($0 + 1) % 7] }
        }
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }
}
