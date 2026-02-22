import Foundation

struct EventStatusSnapshot: Equatable {
    let status: EventStatus
    let leftLabel: String
    let rightLabel: String
    let startLabel: String
    let endLabel: String
    let etaLabel: String
    let progress: Double?
    let waitProgress: Double?
    let startDate: Date?
    let endDate: Date?
}

@MainActor
enum EventStatusResolver {
    private static let tokyoTimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    private static let tokyoCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyoTimeZone
        return calendar
    }()

    static func resolve(startAt: Date?, endAt: Date?, now: Date = Date()) -> EventStatus {
        snapshot(startAt: startAt, endAt: endAt, now: now).status
    }

    static func progress(startAt: Date?, endAt: Date?, now: Date = Date()) -> Double? {
        let status = snapshot(startAt: startAt, endAt: endAt, now: now)
        switch status.status {
        case .ongoing:
            return status.progress
        case .upcoming:
            guard let startAt else { return nil }
            let secondsToStart = startAt.timeIntervalSince(now)
            if secondsToStart > 24 * 60 * 60 {
                return nil
            }
            return status.waitProgress
        case .ended:
            return 1
        case .unknown:
            return nil
        }
    }

    static func snapshot(startAt: Date?, endAt: Date?, now: Date = Date()) -> EventStatusSnapshot {
        guard let startAt else {
            return EventStatusSnapshot( 
                status: .unknown,
                leftLabel: L10n.Common.unknownTime,
                rightLabel: L10n.Common.startUnknown,
                startLabel: "--:--",
                endLabel: "--:--",
                etaLabel: "",
                progress: nil,
                waitProgress: nil,
                startDate: nil,
                endDate: nil
            )
        }

        let startLabel = formatHm(startAt)
        let endLabel: String
        if let endAt {  
            endLabel = formatHm(endAt)
        } else {
            endLabel = "--:--"
        }

        if let endAt, endAt >= startAt, now >= startAt, now <= endAt {
            if tokyoCalendar.startOfDay(for: startAt) != tokyoCalendar.startOfDay(for: endAt) {
                return multiDaySnapshot(startAt: startAt, endAt: endAt, now: now)
            }
            let total = max(endAt.timeIntervalSince(startAt), 1)
            let passed = now.timeIntervalSince(startAt)
            let remainSec = max(Int(ceil(endAt.timeIntervalSince(now))), 0)
            return EventStatusSnapshot(
                status: .ongoing,
                leftLabel: L10n.EventStatus.leftRemaining(formatCountdownByGranularity(remainSec)),
                rightLabel: L10n.EventStatus.rightEndAt(formatHm(endAt)),
                startLabel: startLabel,
                endLabel: endLabel,
                etaLabel: formatCountdownByGranularity(remainSec),
                progress: min(max(passed / total, 0), 1),
                waitProgress: 1,
                startDate: startAt,
                endDate: endAt
            )
        }

        if now < startAt {
            let diffSec = max(Int(ceil(startAt.timeIntervalSince(now))), 1)
            let eta = formatCountdownByGranularity(diffSec)
            let diffMinutes = max(Int(ceil(Double(diffSec) / 60)), 1)
            return EventStatusSnapshot(
                status: .upcoming,
                leftLabel: L10n.EventStatus.leftStartsIn(eta),
                rightLabel: L10n.EventStatus.rightStartAt(startLabel),
                startLabel: startLabel,
                endLabel: endLabel,
                etaLabel: eta,
                progress: 0,
                waitProgress: min(max(1 - (Double(diffMinutes) / 180), 0), 1),
                startDate: startAt,
                endDate: endAt
            )
        }

        return EventStatusSnapshot(
            status: .ended,
            leftLabel: L10n.EventStatus.ended,
            rightLabel: endAt.map { L10n.EventStatus.rightEndAt(formatHm($0)) } ?? L10n.EventStatus.endOnly,
            startLabel: startLabel,
            endLabel: endLabel,
            etaLabel: "00:00:00",
            progress: 1,
            waitProgress: 1,
            startDate: startAt,
            endDate: endAt
        )
    }

    private static func multiDaySnapshot(startAt: Date, endAt: Date, now: Date) -> EventStatusSnapshot {
        let calendar = tokyoCalendar
        let startDay = calendar.startOfDay(for: startAt)
        let endDay = calendar.startOfDay(for: endAt)
        let nowDay = calendar.startOfDay(for: now)
        let startLabel = formatHm(startAt)
        let endLabel = formatHm(endAt)

        if nowDay < startDay {
            return upcomingSnapshot(
                targetStart: startAt,
                now: now,
                startLabel: startLabel,
                endLabel: endLabel,
                endDate: endAt
            )
        }
        if nowDay > endDay {
            return endedSnapshot(startAt: startAt, endAt: endAt, startLabel: startLabel, endLabel: endLabel)
        }

        let startComponents = calendar.dateComponents([.hour, .minute], from: startAt)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endAt)
        guard
            let dayStart = calendar.date(
                bySettingHour: startComponents.hour ?? 0,
                minute: startComponents.minute ?? 0,
                second: 0,
                of: nowDay
            ),
            let rawDayEnd = calendar.date(
                bySettingHour: endComponents.hour ?? 23,
                minute: endComponents.minute ?? 59,
                second: 0,
                of: nowDay
            )
        else {
            return endedSnapshot(startAt: startAt, endAt: endAt, startLabel: startLabel, endLabel: endLabel)
        }

        let dayEnd: Date = {
            if rawDayEnd > dayStart {
                return rawDayEnd
            }
            return calendar.date(byAdding: .day, value: 1, to: rawDayEnd) ?? rawDayEnd
        }()

        if now < dayStart {
            return upcomingSnapshot(
                targetStart: dayStart,
                now: now,
                startLabel: startLabel,
                endLabel: endLabel,
                endDate: endAt
            )
        }

        if now <= dayEnd {
            let total = max(dayEnd.timeIntervalSince(dayStart), 1)
            let passed = now.timeIntervalSince(dayStart)
            let remainSec = max(Int(ceil(dayEnd.timeIntervalSince(now))), 0)
            return EventStatusSnapshot(
                status: .ongoing,
                leftLabel: L10n.EventStatus.leftRemaining(formatCountdownByGranularity(remainSec)),
                rightLabel: L10n.EventStatus.rightEndAt(formatHm(dayEnd)),
                startLabel: startLabel,
                endLabel: endLabel,
                etaLabel: formatCountdownByGranularity(remainSec),
                progress: min(max(passed / total, 0), 1),
                waitProgress: 1,
                startDate: startAt,
                endDate: endAt
            )
        }

        if nowDay < endDay,
           let nextStart = calendar.date(byAdding: .day, value: 1, to: dayStart) {
            return upcomingSnapshot(
                targetStart: nextStart,
                now: now,
                startLabel: startLabel,
                endLabel: endLabel,
                endDate: endAt
            )
        }

        return endedSnapshot(startAt: startAt, endAt: endAt, startLabel: startLabel, endLabel: endLabel)
    }

    private static func upcomingSnapshot(
        targetStart: Date,
        now: Date,
        startLabel: String,
        endLabel: String,
        endDate: Date?
    ) -> EventStatusSnapshot {
        let diffSec = max(Int(ceil(targetStart.timeIntervalSince(now))), 1)
        let eta = formatCountdownByGranularity(diffSec)
        let diffMinutes = max(Int(ceil(Double(diffSec) / 60)), 1)
        return EventStatusSnapshot(
            status: .upcoming,
            leftLabel: L10n.EventStatus.leftStartsIn(eta),
            rightLabel: L10n.EventStatus.rightStartAt(formatHm(targetStart)),
            startLabel: startLabel,
            endLabel: endLabel,
            etaLabel: eta,
            progress: 0,
            waitProgress: min(max(1 - (Double(diffMinutes) / 180), 0), 1),
            startDate: targetStart,
            endDate: endDate
        )
    }

    private static func endedSnapshot(
        startAt: Date,
        endAt: Date?,
        startLabel: String,
        endLabel: String
    ) -> EventStatusSnapshot {
        EventStatusSnapshot(
            status: .ended,
            leftLabel: L10n.EventStatus.ended,
            rightLabel: endAt.map { L10n.EventStatus.rightEndAt(formatHm($0)) } ?? L10n.EventStatus.endOnly,
            startLabel: startLabel,
            endLabel: endLabel,
            etaLabel: "00:00:00",
            progress: 1,
            waitProgress: 1,
            startDate: startAt,
            endDate: endAt
        )
    }

    private static func formatHm(_ date: Date) -> String {
        let components = tokyoCalendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return "\(String(format: "%02d", hour)):\(String(format: "%02d", minute))"
    }

    private static func formatCountdownByGranularity(_ totalSeconds: Int) -> String {
        let safe = max(totalSeconds, 0)
        let days = safe / 86_400
        let hours = safe / 3_600
        let minutes = (safe % 3_600) / 60
        let seconds = safe % 60

        if safe >= 86_400 {
            return L10n.EventStatus.countdownDaysHours(days: days, hours: hours % 24)
        }
        if safe >= 3_600 {
            return L10n.EventStatus.countdownHoursMinutesSeconds(hours: hours, minutes: minutes, seconds: seconds)
        }
        if safe >= 300 {
            return L10n.EventStatus.countdownMinutesSeconds(minutes: safe / 60, seconds: seconds)
        }
        return L10n.EventStatus.countdownSeconds(safe)
    }
}
