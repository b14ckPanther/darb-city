import XCTest
@testable import Darb

final class OpenHoursTests: XCTestCase {
    override func setUp() { Lang.current = .he }

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return c
    }()

    /// Sunday 22 November 2026 at the given time.
    private func sunday(_ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: h, minute: m))!
    }

    private func hours(_ json: String) throws -> Hours {
        try JSONDecoder().decode(Hours.self, from: Data(json.utf8))
    }

    func testOpenUntilClosing() throws {
        let h = try hours(#"{"0":[["08:00","22:00"]]}"#)
        let s = OpenHours.status(h, at: sunday(12), calendar: cal)
        XCTAssertEqual(s.state, .open)
        XCTAssertEqual(s.text.plain, "פתוח עד 22:00")
    }

    func testClosingSoon() throws {
        let h = try hours(#"{"0":[["08:00","22:00"]]}"#)
        let s = OpenHours.status(h, at: sunday(21, 30), calendar: cal)
        XCTAssertEqual(s.state, .closingSoon)
        XCTAssertEqual(s.text.plain, "נסגר בעוד 30 דק׳")
    }

    func testClosedThenOpensLater() throws {
        let h = try hours(#"{"0":[["17:00","23:00"]]}"#)
        let s = OpenHours.status(h, at: sunday(9), calendar: cal)
        XCTAssertEqual(s.state, .closed)
        XCTAssertEqual(s.text.plain, "סגור, נפתח ב 17:00")
    }

    func testRunsPastMidnightFromYesterday() throws {
        // Saturday 18:00 until 02:00 covers Sunday 01:00.
        let h = try hours(#"{"6":[["18:00","02:00"]]}"#)
        let s = OpenHours.status(h, at: sunday(1), calendar: cal)
        XCTAssertTrue(s.isOpen)
    }

    func testAllDay() throws {
        let h = try hours(#"{"0":[["00:00","24:00"]]}"#)
        XCTAssertEqual(OpenHours.status(h, at: sunday(3), calendar: cal).text, "פתוח 24 שעות")
    }

    func testAppointmentAndUnknown() throws {
        XCTAssertEqual(OpenHours.status(try hours(#""appt""#), at: sunday(10), calendar: cal).state, .appointment)
        XCTAssertEqual(OpenHours.status(try hours("null"), at: sunday(10), calendar: cal).text, "אין שעות פתיחה")
    }

    func testRankPutsOpenFirst() {
        XCTAssertLessThan(Status(state: .open, text: "", short: "").rank, Status(state: .appointment, text: "", short: "").rank)
        XCTAssertLessThan(Status(state: .appointment, text: "", short: "").rank, Status(state: .closed, text: "", short: "").rank)
    }
}

@MainActor
final class SearchTests: XCTestCase {
    override func setUp() { Lang.current = .he }

    func testReadsKindAndTown() {
        let store = Store()
        let p = store.parse("מוסך בשפרעם")
        XCTAssertEqual(p.kind, "garages")
        XCTAssertEqual(p.place, "shefaram")
        XCTAssertEqual(p.text, "")
    }

    func testSearchFindsByName() {
        let store = Store()
        let r = store.search("פז")
        XCTAssertFalse(r.isEmpty)
        XCTAssertTrue(r.allSatisfy { $0.business.names.searchKey.contains("פז") || ($0.business.tags?.searchKey ?? "").contains("פז") })
    }

    func testEntriesPutOpenFirst() {
        let store = Store()
        let e = store.entries(kinds: ["stations"])
        let firstClosed = e.firstIndex { !$0.status.isOpen } ?? e.count
        XCTAssertTrue(e[firstClosed...].allSatisfy { !$0.status.isOpen })
    }
}

extension String {
    /// Without the invisible marks that keep a number or a name in its own direction inside a right to left phrase.
    var plain: String { String(unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) && $0.value != 0x200E && $0.value != 0x200F }) }
}
