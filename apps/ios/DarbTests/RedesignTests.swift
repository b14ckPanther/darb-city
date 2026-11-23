import XCTest
@testable import Darb

final class RedesignTests: XCTestCase {
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
    private func hours(_ json: String) throws -> Hours { try JSONDecoder().decode(Hours.self, from: Data(json.utf8)) }
    private func place(_ name: String, kind: String = "restaurants", tag: String? = "מסעדה") -> Business {
        Business(id: 1, name: name, kind: kind, place: "sakhnin", lat: 32.86, lng: 35.3, km: 1, hours: .unknown, demoHours: true, tag: tag)
    }
    private let food = Need.byKey("food")
    private let all: (String) -> Bool = { _ in true }

    // MARK: the next opening

    func testNextOpeningLaterToday() throws {
        let h = try hours(#"{"0":[["17:00","23:00"]]}"#)
        XCTAssertEqual(OpenHours.nextOpening(h, after: sunday(9), calendar: cal), sunday(17))
    }

    func testNextOpeningTomorrowAfterClosing() throws {
        let h = try hours(#"{"0":[["08:00","18:00"]],"1":[["08:30","18:00"]]}"#)
        let next = OpenHours.nextOpening(h, after: sunday(20), calendar: cal)
        XCTAssertEqual(next, cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 8, minute: 30)))
    }

    func testNextOpeningSkipsClosedDays() throws {
        let h = try hours(#"{"3":[["10:00","14:00"]]}"#)
        let next = OpenHours.nextOpening(h, after: sunday(12), calendar: cal)
        XCTAssertEqual(next, cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 10)))
    }

    func testNoNextOpeningWithoutWeeklyHours() {
        XCTAssertNil(OpenHours.nextOpening(.appointment, after: sunday(12), calendar: cal))
        XCTAssertNil(OpenHours.nextOpening(.unknown, after: sunday(12), calendar: cal))
    }

    // MARK: the picture for a business

    func testCuisineFromTheSourceComesFirst() {
        let b = place("מלך הפיצה והבורגר", tag: "מסעדה, המבורגר")
        XCTAssertEqual(ArtResolver.resolve(b, need: food, sector: nil, exists: all).render, "p-burger")
    }

    func testNameSpeaksWhenTheTagSaysOnlyRestaurant() {
        XCTAssertEqual(ArtResolver.resolve(place("פיצה רבין"), need: food, sector: nil, exists: all).render, "p-pizza")
        XCTAssertEqual(ArtResolver.resolve(place("שווארמה הכיכר"), need: food, sector: nil, exists: all).render, "p-shawarma")
    }

    func testMissingRenderFallsThroughToTheNeed() {
        let onlyPlate: (String) -> Bool = { $0 == "p-plate" }
        XCTAssertEqual(ArtResolver.resolve(place("בורגרים", tag: "מסעדה, המבורגר"), need: food, sector: nil, exists: onlyPlate).render, "p-plate")
    }

    func testKindWithoutARenderGetsASymbolOnItsSectorColour() {
        let sector = Sector(slug: "health", name: Tri("בריאות"), accent: "#a7c2b1")
        let art = ArtResolver.resolve(place("ד״ר כהן", kind: "dental", tag: nil), need: nil, sector: sector) { _ in false }
        XCTAssertNil(art.render)
        XCTAssertEqual(art.symbol, "cross.case.fill")
        XCTAssertEqual(art.tint, "#a7c2b1")
    }

    func testHousesOfPrayerShareOneNeutralPicture() {
        for kind in ["synagogues", "mosques", "churches"] {
            let art = ArtResolver.resolve(place("בית תפילה", kind: kind, tag: nil), need: nil, sector: nil, exists: all)
            XCTAssertEqual(art.render, "p-community")
            XCTAssertEqual(art.symbol, "building.columns.fill")
        }
    }

    // MARK: the widget and Siri

    func testAnswersPutAnOpenPlaceBeforeANearerClosedOne() throws {
        let open = try hours(#"{"0":[["08:00","22:00"]]}"#), shut = try hours(#"{"0":[["08:00","10:00"]]}"#)
        let near = Business(id: 1, name: "קרוב וסגור", kind: "pharmacies", place: "a", lat: 0, lng: 0, km: 1, hours: shut, demoHours: false, tag: nil)
        let far = Business(id: 2, name: "רחוק ופתוח", kind: "pharmacies", place: "a", lat: 0, lng: 0, km: 5, hours: open, demoHours: false, tag: nil)
        let data = DarbData(home: "a", sectors: [], kinds: [], places: [], businesses: [near, far])
        let answers = Nearest.answers(in: data, at: sunday(12), calendar: cal)
        XCTAssertEqual(answers.first { $0.need.key == "pharmacy" }?.business.id, 2)
    }

    // MARK: open when you get there

    func testOpenOnArrivalWhenThereIsTimeToSpare() throws {
        let h = try hours(#"{"0":[["08:00","22:00"]]}"#)
        XCTAssertTrue(OpenHours.openOnArrival(h, at: sunday(21), drive: 20, calendar: cal))
    }

    func testNotOpenOnArrivalWhenTheDriveIsLongerThanTheTimeLeft() throws {
        let h = try hours(#"{"0":[["08:00","22:00"]]}"#)
        XCTAssertEqual(OpenHours.minutesLeft(h, at: sunday(21, 45), calendar: cal), 15)
        XCTAssertFalse(OpenHours.openOnArrival(h, at: sunday(21, 45), drive: 20, calendar: cal))
    }

    func testAllDayAndPastMidnightStayOpenOnArrival() throws {
        let allDay = try hours(#"{"0":[["00:00","24:00"]]}"#)
        XCTAssertTrue(OpenHours.openOnArrival(allDay, at: sunday(23, 50), drive: 30, calendar: cal))
        let late = try hours(#"{"0":[["18:00","02:00"]]}"#)
        XCTAssertEqual(OpenHours.minutesLeft(late, at: sunday(23, 30), calendar: cal), 150)
        XCTAssertTrue(OpenHours.openOnArrival(late, at: sunday(23, 30), drive: 45, calendar: cal))
    }

    func testAClosedPlaceIsNotOpenOnArrival() throws {
        let h = try hours(#"{"0":[["08:00","12:00"]]}"#)
        XCTAssertFalse(OpenHours.openOnArrival(h, at: sunday(13), drive: 5, calendar: cal))
    }

    func testAnswersPreferAPlaceThatStaysOpenOverANearerOneThatWillClose() throws {
        let closing = try hours(#"{"0":[["08:00","12:10"]]}"#), staying = try hours(#"{"0":[["08:00","22:00"]]}"#)
        // 12 km is about 21 minutes away, and it closes in 10
        let far = Business(id: 1, name: "נסגר לפני שמגיעים", kind: "pharmacies", place: "a", lat: 0, lng: 0, km: 12, hours: closing, demoHours: false, tag: nil)
        let further = Business(id: 2, name: "נשאר פתוח", kind: "pharmacies", place: "a", lat: 0, lng: 0, km: 14, hours: staying, demoHours: false, tag: nil)
        let data = DarbData(home: "a", sectors: [], kinds: [], places: [], businesses: [far, further])
        XCTAssertEqual(Nearest.answers(in: data, at: sunday(12), calendar: cal).first { $0.need.key == "pharmacy" }?.business.id, 2)
    }
}

@MainActor
final class MoneyTests: XCTestCase {
    /// Nobody pays yet, so no placement may show a business: the slots fall back to Darb's own card.
    func testNoSponsorIsEverMadeUp() {
        let store = Store()
        XCTAssertTrue(store.promo.sponsorships.isEmpty)
        XCTAssertNil(store.homeSponsor)
        XCTAssertNil(store.pageSponsor(kinds: ["stations"], nearest: store.entries(kinds: ["stations"]).first))
    }

    /// Payment never buys rank: the first answer for a need is the nearest of the places that rank best, whoever they are.
    func testTheAnswerIsTheNearestOfTheBestRanked() {
        let store = Store()
        for need in Need.all {
            let all = store.entries(kinds: need.kinds)
            guard let first = all.first else { continue }
            XCTAssertEqual(first.business.km, all.filter { $0.rank == first.rank }.map(\.business.km).min())
            XCTAssertEqual(first.rank, all.map(\.rank).min())
        }
    }

    func testRealClientsHaveProfilesAndFreeListingsDoNot() {
        let store = Store()
        XCTAssertEqual(store.promo.profiles.count, 4)
        for p in store.promo.profiles {
            XCTAssertNotNil(store.business(p.id))
            XCTAssertTrue(store.isPaid(p))
            // no picture is ever made up
            XCTAssertNil(p.logo); XCTAssertNil(p.cover); XCTAssertNil(p.storefront); XCTAssertTrue(p.photos.isEmpty)
        }
        XCTAssertFalse(store.isPaid(store.profile(0)))
    }

    func testEventsAreCountedPerBusiness() {
        let defaults = UserDefaults(suiteName: "darb.tests.analytics")!
        defaults.removePersistentDomain(forName: "darb.tests.analytics")
        Analytics.log(.navigate, 7, in: defaults)
        Analytics.log(.navigate, 7, in: defaults)
        Analytics.log(.call, 7, in: defaults)
        XCTAssertEqual(Analytics.count(.navigate, 7, in: defaults), 2)
        XCTAssertEqual(Analytics.count(.call, 7, in: defaults), 1)
        XCTAssertEqual(Analytics.count(.navigate, 8, in: defaults), 0)
        XCTAssertEqual(Analytics.pending(in: defaults).map(\.event), [.navigate, .navigate, .call])
    }
}
