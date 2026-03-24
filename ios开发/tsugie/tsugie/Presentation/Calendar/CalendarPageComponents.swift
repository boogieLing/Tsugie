import SwiftUI

struct CalendarCategoryMeta: Identifiable {
    let id: String
    let label: String
    let iconName: String
}

struct CalendarScoredItem: Identifiable {
    let id: UUID
    let place: HePlace
    let snapshot: EventStatusSnapshot
    let distanceMeters: Double
    let categoryID: String
    let dayKey: String
}

struct CalendarBucket: Identifiable, Equatable {
    let id: String
    let dayDate: Date
    let counts: [String: Int]
    let totalCount: Int
}

struct CalendarMonthBlock: Identifiable, Equatable {
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

let calendarDayCellCategoryIDs = ["hanabi", "matsuri", "nature", "other"]

struct CalendarPrewarmedPayload {
    let signature: String
    let localeIdentifier: String
    let bucketsByDayKey: [String: CalendarBucket]
    let monthBlockPool: [String: CalendarMonthBlock]
}

struct DayDrawerFilterRail: View {
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
        AnyShapeStyle(Color.white)
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

struct CalendarMonthPagerView: View, Equatable {
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

struct CalendarMonthBlockView: View, Equatable {
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

struct CalendarDayCellView: View, Equatable {
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
