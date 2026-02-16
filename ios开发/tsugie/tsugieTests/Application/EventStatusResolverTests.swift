import XCTest
@testable import tsugie

@MainActor
final class EventStatusResolverTests: XCTestCase {
    func testResolveUnknownWhenStartDateMissing() {
        let result = EventStatusResolver.resolve(startAt: nil, endAt: nil, now: fixedDate(hour: 12))
        XCTAssertEqual(result, .unknown)
    }

    func testResolveUpcomingWhenNowBeforeStartDate() {
        let now = fixedDate(hour: 12)
        let start = now.addingTimeInterval(90 * 60)
        let end = now.addingTimeInterval(4 * 60 * 60)

        let snapshot = EventStatusResolver.snapshot(startAt: start, endAt: end, now: now)

        XCTAssertEqual(snapshot.status, .upcoming)
        XCTAssertEqual(snapshot.progress, 0)
        XCTAssertNotNil(snapshot.waitProgress)
    }

    func testResolveOngoingAndProgressInRange() {
        let start = fixedDate(hour: 10)
        let end = fixedDate(hour: 12)
        let now = fixedDate(hour: 11)

        let snapshot = EventStatusResolver.snapshot(startAt: start, endAt: end, now: now)

        XCTAssertEqual(snapshot.status, .ongoing)
        XCTAssertEqual(snapshot.progress ?? -1, 0.5, accuracy: 0.001)
    }

    func testResolveEndedWhenNowAfterEndDate() {
        let now = fixedDate(hour: 14)
        let start = fixedDate(hour: 10)
        let end = fixedDate(hour: 12)

        let result = EventStatusResolver.resolve(startAt: start, endAt: end, now: now)
        XCTAssertEqual(result, .ended)
        XCTAssertEqual(EventStatusResolver.progress(startAt: start, endAt: end, now: now), 1)
    }

    func testProgressReturnsNilForUpcomingOver24HoursAway() {
        let now = fixedDate(hour: 9)
        let start = now.addingTimeInterval(25 * 60 * 60)
        let end = start.addingTimeInterval(2 * 60 * 60)

        let progress = EventStatusResolver.progress(startAt: start, endAt: end, now: now)
        XCTAssertNil(progress)
    }

    func testResolveMultiDayUsesDailyWindowOutsideHoursAsUpcoming() {
        let start = fixedDate(day: 10, hour: 9)
        let end = fixedDate(day: 12, hour: 21)
        let now = fixedDate(day: 11, hour: 6)

        let snapshot = EventStatusResolver.snapshot(startAt: start, endAt: end, now: now)

        XCTAssertEqual(snapshot.status, .upcoming)
    }

    func testResolveMultiDayUsesDailyWindowAfterFinalCloseAsEnded() {
        let start = fixedDate(day: 10, hour: 9)
        let end = fixedDate(day: 12, hour: 21)
        let now = fixedDate(day: 12, hour: 22)

        let snapshot = EventStatusResolver.snapshot(startAt: start, endAt: end, now: now)

        XCTAssertEqual(snapshot.status, .ended)
    }

    private func fixedDate(day: Int = 15, hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 2
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
