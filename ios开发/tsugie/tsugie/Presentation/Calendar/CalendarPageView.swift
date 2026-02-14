import SwiftUI

private struct CalendarCategoryMeta: Identifiable {
    let id: String
    let label: String
    let logo: String
}

private struct CalendarScoredItem: Identifiable {
    let id = UUID()
    let place: HePlace
    let snapshot: EventStatusSnapshot
    let distanceMeters: Double
    let categoryID: String
    let dayKey: String
}

private struct CalendarBucket: Identifiable {
    let id: String
    let dayDate: Date
    let items: [CalendarScoredItem]
    let counts: [String: Int]
}

private struct CalendarMonthBlock: Identifiable {
    struct Cell: Identifiable {
        let id = UUID()
        let day: Int?
        let dayKey: String?
        let date: Date?
        let bucket: CalendarBucket?
    }

    let id: String
    let title: String
    let cells: [Cell]
}

struct CalendarPageView: View {
    let places: [HePlace]
    let placeStateProvider: (UUID) -> PlaceState
    let onClose: () -> Void
    let onSelectPlace: (UUID) -> Void
    let now: Date

    @State private var selectedDayKey: String?
    @State private var dayFilterID = "all"

    private let categories: [CalendarCategoryMeta] = [
        .init(id: "all", label: "全部", logo: "◎"),
        .init(id: "hanabi", label: "花火", logo: "花"),
        .init(id: "matsuri", label: "祭典", logo: "祭"),
        .init(id: "nature", label: "景観", logo: "景"),
        .init(id: "other", label: "その他", logo: "他")
    ]
    private let activeGradient = TsugieVisuals.pillGradient
    private let activeGlowColor = TsugieVisuals.mapGlowColor(scheme: "fresh", alphaRatio: 1.0, saturationRatio: 1.2)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundLayer

                VStack(spacing: 0) {
                    header
                    monthList
                }

                if isDayDrawerOpen {
                    dayDrawerLayer(proxy: proxy)
                }
            }
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("時めぐりカレンダー")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color(red: 0.19, green: 0.35, blue: 0.42))
                Text("時間軸のへ統計（マップは位置軸）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.55))
            }

            Spacer()

            Button(action: onClose) {
                Text("⌄")
                    .font(.system(size: 17))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.82), in: Circle())
                    .overlay(Circle().stroke(Color(red: 0.84, green: 0.92, blue: 0.94, opacity: 0.9), lineWidth: 1))
                    .foregroundStyle(Color(red: 0.36, green: 0.49, blue: 0.54))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("カレンダーを閉じる")
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var monthList: some View {
        ScrollView {
            VStack(spacing: 8) {
                let blocks = buildCalendarMonths()
                if blocks.isEmpty {
                    Text("この期間のへはありません。")
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
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func monthBlock(_ block: CalendarMonthBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color(red: 0.21, green: 0.37, blue: 0.44))
                .padding(.horizontal, 4)

            HStack(spacing: 6) {
                ForEach(Array(["日", "月", "火", "水", "木", "金", "土"].enumerated()), id: \.offset) { index, label in
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
        .padding(.vertical, 6)
    }

    private func calendarDayCell(day: Int, dayKey: String, date: Date?, bucket: CalendarBucket?) -> some View {
        let isToday = dayKey == dayKeyOf(now)
        let isWeekend: Int = date.map { Calendar.current.component(.weekday, from: $0) } ?? 0
        let dayColor: Color = isWeekend == 1 ? Color(red: 0.88, green: 0.47, blue: 0.53) : (isWeekend == 7 ? Color(red: 0.35, green: 0.53, blue: 0.79) : Color(red: 0.24, green: 0.38, blue: 0.44))

        return Button {
            guard bucket != nil else { return }
            selectedDayKey = dayKey
            dayFilterID = "all"
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(day)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(dayColor)

                if let bucket {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(categories.filter { $0.id != "all" }, id: \.id) { category in
                            if let count = bucket.counts[category.id], count > 0 {
                                HStack(spacing: 4) {
                                    Text(category.logo)
                                        .font(.system(size: 9, weight: .heavy))
                                        .frame(width: 14, height: 14)
                                        .background(Color.white.opacity(0.88), in: Circle())
                                        .overlay(Circle().stroke(Color(red: 0.81, green: 0.90, blue: 0.93, opacity: 0.86), lineWidth: 1))
                                        .foregroundStyle(Color(red: 0.31, green: 0.44, blue: 0.50))
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(Color(red: 0.35, green: 0.47, blue: 0.53))
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(4)
            .background(cellBackground(isToday: isToday), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(bucket == nil ? .clear : Color(red: 0.85, green: 0.92, blue: 0.95, opacity: 0.86), lineWidth: bucket == nil ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(bucket == nil)
    }

    private func cellBackground(isToday: Bool) -> some ShapeStyle {
        if isToday {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        Color.white.opacity(0.82),
                        Color(red: 0.90, green: 0.98, blue: 1.0, opacity: 0.80)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.64))
    }

    private func dayDrawerLayer(proxy: GeometryProxy) -> some View {
        let width = min(proxy.size.width * 0.80, 298)

        return ZStack {
            Button {
                selectedDayKey = nil
                dayFilterID = "all"
            } label: {
                Color(red: 0.11, green: 0.23, blue: 0.29, opacity: 0.16)
                    .ignoresSafeArea()
            }
            .buttonStyle(.plain)

            HStack {
                Spacer()
                dayDrawer(width: width)
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .transition(.opacity)
    }

    private func dayDrawer(width: CGFloat) -> some View {
        let bucket = selectedBucket

        return VStack(spacing: 10) {
            HStack {
                Text(bucket.map { "\(dayTitleOf($0.dayDate)) のへ" } ?? "日付のへ")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color(red: 0.21, green: 0.37, blue: 0.43))
                Spacer()
                Button {
                    selectedDayKey = nil
                    dayFilterID = "all"
                } label: {
                    Text("×")
                        .font(.system(size: 18))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.72), in: Circle())
                        .overlay(Circle().stroke(Color(red: 0.83, green: 0.91, blue: 0.95, opacity: 0.9), lineWidth: 1))
                        .foregroundStyle(Color(red: 0.37, green: 0.50, blue: 0.54))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let bucket {
                        Text("時間軸から抽出。並び順は近さと開始の早さを優先。")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))

                        dayFilterChips(bucket)

                        VStack(spacing: 8) {
                            ForEach(filteredDayItems(bucket), id: \.id) { item in
                                dayItemRow(item)
                            }

                            if filteredDayItems(bucket).isEmpty {
                                Text("該当なし")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(red: 0.39, green: 0.51, blue: 0.56))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        Text("選択した日のへはありません。")
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
        .shadow(color: Color(red: 0.11, green: 0.30, blue: 0.38, opacity: 0.16), radius: 16, x: 0, y: 10)
    }

    private func dayFilterChips(_ bucket: CalendarBucket) -> some View {
        let ids = ["all"] + categories
            .map(\.id)
            .filter { $0 != "all" && (bucket.counts[$0] ?? 0) > 0 }

        return HStack(spacing: 6) {
            ForEach(ids, id: \.self) { id in
                let category = categories.first(where: { $0.id == id }) ?? categories[0]
                let count = id == "all" ? bucket.items.count : (bucket.counts[id] ?? 0)
                let isActive = dayFilterID == id
                Button {
                    dayFilterID = id
                } label: {
                    HStack(spacing: 6) {
                        Text(category.logo)
                            .font(.system(size: 10, weight: .heavy))
                            .frame(width: 15, height: 15)
                            .background(Color.white.opacity(0.92), in: Circle())
                            .overlay(Circle().stroke(Color(red: 0.80, green: 0.89, blue: 0.93, opacity: 0.88), lineWidth: 1))
                        Text(category.label)
                        Text("\(count)")
                            .foregroundStyle(Color(red: 0.33, green: 0.46, blue: 0.52))
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(isActive ? AnyShapeStyle(Color.white.opacity(0.9)) : AnyShapeStyle(Color.white.opacity(0.68)), in: Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.84, green: 0.92, blue: 0.95, opacity: 0.9), lineWidth: isActive ? 0 : 1))
                    .foregroundStyle(Color(red: 0.27, green: 0.41, blue: 0.47))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dayItemRow(_ item: CalendarScoredItem) -> some View {
        let category = categories.first(where: { $0.id == item.categoryID }) ?? categories[0]
        let state = placeStateProvider(item.place.id)
        return Button {
            selectedDayKey = nil
            dayFilterID = "all"
            onClose()
            onSelectPlace(item.place.id)
        } label: {
            VStack(spacing: 7) {
                HStack(alignment: .center, spacing: 9) {
                    Text(category.logo)
                        .font(.system(size: 11, weight: .heavy))
                        .frame(width: 21, height: 21)
                        .background(Color.white.opacity(0.9), in: Circle())
                        .overlay(Circle().stroke(Color(red: 0.81, green: 0.90, blue: 0.93, opacity: 0.90), lineWidth: 1))
                        .foregroundStyle(Color(red: 0.26, green: 0.44, blue: 0.51))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.place.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(red: 0.16, green: 0.32, blue: 0.40))
                            .lineLimit(1)
                        Text("\(distanceLabel(item.distanceMeters)) ・ \(item.snapshot.startLabel) - \(item.snapshot.endLabel)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.38, green: 0.49, blue: 0.54))
                        Text(item.snapshot.leftLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.31, green: 0.43, blue: 0.48))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 5) {
                        Text(category.label)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.36, green: 0.48, blue: 0.53))
                        PlaceStateIconsView(
                            placeState: state,
                            size: 16,
                            activeGradient: activeGradient,
                            activeGlowColor: activeGlowColor
                        )
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

    private var selectedBucket: CalendarBucket? {
        guard let selectedDayKey else { return nil }
        return buildCalendarBuckets().first(where: { $0.id == selectedDayKey })
    }

    private var isDayDrawerOpen: Bool {
        selectedDayKey != nil
    }

    private func filteredDayItems(_ bucket: CalendarBucket) -> [CalendarScoredItem] {
        if dayFilterID == "all" {
            return bucket.items
        }
        return bucket.items.filter { $0.categoryID == dayFilterID }
    }

    private func buildCalendarBuckets() -> [CalendarBucket] {
        let scored = places.compactMap { place -> CalendarScoredItem? in
            let snapshot = EventStatusResolver.snapshot(startAt: place.startAt, endAt: place.endAt, now: now)
            guard let start = snapshot.startDate else { return nil }
            let key = dayKeyOf(start)
            return CalendarScoredItem(
                place: place,
                snapshot: snapshot,
                distanceMeters: place.distanceMeters,
                categoryID: categoryID(for: place),
                dayKey: key
            )
        }

        let grouped = Dictionary(grouping: scored, by: \.dayKey)
        var buckets: [CalendarBucket] = grouped.compactMap { key, items in
            guard let date = items.first?.snapshot.startDate else { return nil }
            let sorted = items.sorted(by: recommendationCompare)
            var counts: [String: Int] = [:]
            sorted.forEach { counts[$0.categoryID, default: 0] += 1 }
            return CalendarBucket(id: key, dayDate: date, items: sorted, counts: counts)
        }
        buckets.sort { $0.dayDate < $1.dayDate }
        return buckets
    }

    private func buildCalendarMonths() -> [CalendarMonthBlock] {
        let buckets = buildCalendarBuckets()
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

            for _ in 0..<firstWeekday {
                cells.append(.init(day: nil, dayKey: nil, date: nil, bucket: nil))
            }

            for day in 1...daysInMonth {
                let date = DateComponents(calendar: .current, year: year, month: month, day: day).date
                let key = date.map(dayKeyOf) ?? ""
                cells.append(.init(day: day, dayKey: key, date: date, bucket: bucketMap[key]))
            }

            blocks.append(
                CalendarMonthBlock(
                    id: "\(year)-\(String(format: "%02d", month))",
                    title: "\(year)年\(month)月",
                    cells: cells
                )
            )

            cursor = Calendar.current.date(byAdding: .month, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }

        return blocks
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
        let week = ["日", "月", "火", "水", "木", "金", "土"]
        let m = Calendar.current.component(.month, from: date)
        let d = Calendar.current.component(.day, from: date)
        let w = week[(Calendar.current.component(.weekday, from: date) + 6) % 7]
        return "\(m)/\(d) (\(w))"
    }

    private func distanceLabel(_ meters: Double) -> String {
        let safe = max(meters, 0)
        if safe < 1_000 {
            return "\(Int(max(80, safe.rounded())))m"
        }
        return "\((safe / 1_000).formatted(.number.precision(.fractionLength(1))))km"
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 1.00, blue: 1.00, opacity: 0.96),
                    Color(red: 0.95, green: 1.00, blue: 0.98, opacity: 0.94),
                    Color(red: 0.93, green: 0.97, blue: 1.00, opacity: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.68, green: 0.97, blue: 1.0, opacity: 0.36))
                .frame(width: 320, height: 320)
                .offset(x: -140, y: -300)
            Circle()
                .fill(Color(red: 0.72, green: 0.82, blue: 1.0, opacity: 0.34))
                .frame(width: 360, height: 360)
                .offset(x: 170, y: -280)
        }
    }
}
