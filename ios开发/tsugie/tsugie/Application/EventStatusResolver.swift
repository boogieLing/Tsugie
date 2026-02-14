import Foundation

struct EventStatusSnapshot {
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
                leftLabel: "時刻未定",
                rightLabel: "開始 未定",
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
            let total = max(endAt.timeIntervalSince(startAt), 1)
            let passed = now.timeIntervalSince(startAt)
            let remainSec = max(Int(ceil(endAt.timeIntervalSince(now))), 0)
            return EventStatusSnapshot(
                status: .ongoing,
                leftLabel: "残り\(formatCountdownByGranularity(remainSec))",
                rightLabel: "終了 \(formatHm(endAt))",
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
                leftLabel: "開始まで\(eta)",
                rightLabel: "開始 \(startLabel)",
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
            leftLabel: "終了済み",
            rightLabel: endAt.map { "終了 \(formatHm($0))" } ?? "終了",
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
        let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
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
            return "\(days)日\(hours % 24)時間"
        }
        if safe >= 3_600 {
            return "\(hours)時間\(minutes)分\(seconds)秒"
        }
        if safe >= 300 {
            return "\(safe / 60)分\(seconds)秒"
        }
        return "\(safe)秒"
    }
}
