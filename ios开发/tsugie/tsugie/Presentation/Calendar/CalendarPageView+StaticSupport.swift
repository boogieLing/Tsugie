import SwiftUI

extension CalendarPageView {
    static func buildDetailItems(
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

    static func groupDetailPlacesByDayKey(
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

    static func buildCalendarBuckets(from sourcePlaces: [HePlace], calendar: Calendar) -> [CalendarBucket] {
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

    static func calendarCategoryID(for place: HePlace) -> String {
        switch place.heType {
        case .hanabi: return "hanabi"
        case .matsuri: return "matsuri"
        case .nature: return "nature"
        case .other: return "other"
        }
    }

    static func calendarDayKey(_ date: Date, calendar: Calendar) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "\(y)-\(String(format: "%02d", m))-\(String(format: "%02d", d))"
    }

    static func makePlacesSignature(places: [HePlace]) -> String {
        let placesFirst = places.first?.id.uuidString ?? "nil"
        let placesLast = places.last?.id.uuidString ?? "nil"
        return "\(places.count)|\(placesFirst)|\(placesLast)"
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    nonisolated static func recommendationCompareStatic(_ lhs: CalendarScoredItem, _ rhs: CalendarScoredItem) -> Bool {
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

    static func buildSingleCalendarMonth(
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

    static func calendarMonthKey(_ date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "\(year)-\(String(format: "%02d", month))"
    }

    static func weekdayColumnIndex(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    static func buildMonthBlockPool(
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

    static var defaultWeekdaySymbols: [String] {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    static func buildWeekdaySymbols(locale: Locale) -> [String] {
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
