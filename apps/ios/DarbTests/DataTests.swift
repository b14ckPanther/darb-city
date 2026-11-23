import XCTest
@testable import Darb

/// The bundled data, as scripts/export-data.py writes it.
final class ExportTests: XCTestCase {
    private static let data = DarbData.load()!
    private var data: DarbData { Self.data }

    func testEveryBusinessInTheNorthIsThere() {
        XCTAssertGreaterThan(data.businesses.count, 13_000)
        XCTAssertEqual(data.sectors.count, 18)
        XCTAssertGreaterThan(data.kinds.count, 200)
        XCTAssertGreaterThan(data.places.count, 500)
        // not cut to one town: the data reaches from the coast to the Golan and from Hadera to the border
        XCTAssertLessThan(data.businesses.map(\.lat).min()!, 32.5)
        XCTAssertGreaterThan(data.businesses.map(\.lat).max()!, 33.2)
        XCTAssertLessThan(data.businesses.map(\.lng).min()!, 34.95)
        XCTAssertGreaterThan(data.businesses.map(\.lng).max()!, 35.7)
    }

    func testIdsAreUniqueAndEveryBusinessHasItsKindAndTown() {
        XCTAssertEqual(Set(data.businesses.map(\.id)).count, data.businesses.count)
        let kinds = Set(data.kinds.map(\.slug)), places = Set(data.places.map(\.slug))
        for b in data.businesses {
            XCTAssertTrue(kinds.contains(b.kind))
            XCTAssertTrue(places.contains(b.place))
        }
        XCTAssertTrue(places.contains(data.home))
    }

    func testNamesComeInAllThreeLanguages() {
        for b in data.businesses {
            XCTAssertFalse(b.names.he.isEmpty); XCTAssertFalse(b.names.ar.isEmpty); XCTAssertFalse(b.names.en.isEmpty)
        }
        for k in data.kinds { XCTAssertFalse(k.name.ar.isEmpty); XCTAssertFalse(k.name.en.isEmpty) }
        for p in data.places { XCTAssertFalse(p.name.ar.isEmpty); XCTAssertFalse(p.name.en.isEmpty) }
        // and they really are different languages, not Hebrew three times
        let sakhnin = data.places.first { $0.slug == "sakhnin" }
        XCTAssertEqual(sakhnin?.name.ar, "سخنين")
        XCTAssertEqual(sakhnin?.name.en, "Sakhnin")
        XCTAssertGreaterThan(data.businesses.filter { $0.names.ar != $0.names.he }.count, 10_000)
    }

    /// Hours that are not the business's own are sample hours, and stay labelled as such.
    func testSampleHoursStayLabelled() {
        let sample = data.businesses.filter(\.demoHours), own = data.businesses.filter { !$0.demoHours }
        XCTAssertGreaterThan(sample.count, 10_000)
        XCTAssertGreaterThan(own.count, 500)
        for b in data.businesses { if case .weekly = b.hours {} else { XCTFail("\(b.names.he) has no week") } }
        // every bank's hours are sample hours: the source gives none
        XCTAssertTrue(data.businesses.filter { $0.kind == "banks" }.allSatisfy(\.demoHours))
    }

    func testDetailsCarryPhonesLinksAndAttributes() {
        let details = DarbData.details()
        let ids = Set(data.businesses.map(\.id))
        XCTAssertTrue(details.keys.allSatisfy(ids.contains))
        XCTAssertGreaterThan(details.values.filter { $0.phone != nil }.count, 2_000)
        XCTAssertGreaterThan(details.values.filter { $0.web != nil }.count, 1_000)
        XCTAssertGreaterThan(details.values.filter { $0.links?.facebook != nil }.count, 300)
        XCTAssertGreaterThan(details.values.filter { $0.attr?.bankCode != nil }.count, 200)
        XCTAssertGreaterThan(details.values.filter { $0.attr?.wheelchair == true }.count, 100)
    }

    func testNoOffCopyWordsInWhatTheAppShowsAboutAPlace() {
        let off = OffCopy(#"חלאל|(?<![א-ת])כשר(?![א-ת])|حلال|halal|kosher"#)
        for b in data.businesses {
            guard let t = b.tags else { continue }
            let text = (t.he + " " + t.ar + " " + t.en).lowercased()
            XCTAssertFalse(off.isIn(text), text)
        }
    }

    /// The widget and Siri read needs.json: the same places for the nine needs, and nothing else.
    func testNeedsFileCoversTheEverydayNeeds() {
        let needs = Nearest.load()!
        let kinds = Set(Need.all.flatMap(\.kinds))
        XCTAssertTrue(needs.businesses.allSatisfy { kinds.contains($0.kind) })
        XCTAssertEqual(needs.businesses.count, data.businesses.filter { kinds.contains($0.kind) }.count)
        XCTAssertLessThan(needs.businesses.count, data.businesses.count / 3)
    }

    func testPlansCarryFeaturesPricesAndNotesInThreeLanguages() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "promo", withExtension: "json"))
        let promo = try JSONDecoder().decode(Promo.self, from: Data(contentsOf: url))
        XCTAssertEqual(promo.plans.map(\.slug), ["presence", "spotlight", "signature", "ecosystem"])
        XCTAssertEqual(promo.plans.map(\.monthly), [0, 89, 349, nil])
        for p in promo.plans {
            for lang in ["he", "ar", "en"] { XCTAssertFalse((p.features[lang] ?? []).isEmpty, "\(p.slug) \(lang)") }
            XCTAssertNotEqual(p.name.he, p.name.ar)
        }
        XCTAssertNotNil(promo.texts["pricing.terms"])
        // nobody has bought a placement, and none is made up
        XCTAssertTrue(promo.sponsorships.isEmpty)
    }

    func testTermsAndPrivacyAreBundledInThreeLanguages() throws {
        let legal = try XCTUnwrap(Legal.load())
        for kind in [LegalKind.terms, .privacy] {
            for lang in Lang.allCases {
                let doc = try XCTUnwrap(legal.docs[kind.rawValue]?[lang.rawValue])
                XCTAssertGreaterThan(doc.sections.count, 5)
            }
        }
    }
}

/// Distances and order come from where the person is.
@MainActor
final class LocationTests: XCTestCase {
    private let karmiel = Coordinate(lat: 32.919, lng: 35.295)
    private let nazareth = Coordinate(lat: 32.699, lng: 35.303)

    func testDistanceBetweenTwoKnownTowns() {
        // Karmiel to Nazareth is about 24.5 km in a straight line
        XCTAssertEqual(Geo.km(karmiel, nazareth), 24.5, accuracy: 0.6)
        XCTAssertEqual(Geo.km(karmiel, karmiel), 0, accuracy: 0.001)
        XCTAssertEqual(Geo.minutes(km: 10), 18)
    }

    func testBearingPointsTheRightWay() {
        // Nazareth lies south of Karmiel, and Karmiel north of Nazareth
        XCTAssertEqual(abs(Geo.bearing(from: karmiel, lat: nazareth.lat, lng: nazareth.lng)), .pi, accuracy: 0.1)
        XCTAssertEqual(Geo.bearing(from: nazareth, lat: karmiel.lat, lng: karmiel.lng), 0, accuracy: 0.1)
        XCTAssertEqual(Geo.bearing(from: karmiel, lat: karmiel.lat, lng: karmiel.lng + 0.1), .pi / 2, accuracy: 0.01)
    }

    func testTheAppMeasuresFromWhereThePersonStands() throws {
        let store = Store()
        store.stand(at: karmiel)
        XCTAssertTrue(store.isLive)
        XCTAssertEqual(store.here, "karmiel")
        let fromKarmiel = try XCTUnwrap(store.entries(kinds: ["stations"]).first)
        let sample = try XCTUnwrap(store.all.first { $0.place == "nazareth" })
        XCTAssertEqual(sample.km, Geo.km(karmiel, lat: sample.lat, lng: sample.lng), accuracy: 0.001)

        store.stand(at: nazareth)
        XCTAssertEqual(store.here, "nazareth")
        let fromNazareth = try XCTUnwrap(store.entries(kinds: ["stations"]).first)
        XCTAssertNotEqual(fromKarmiel.id, fromNazareth.id)
        // every answer is within driving distance of the new position, and the nearest of its rank
        let all = store.entries(kinds: ["stations"])
        XCTAssertTrue(all.allSatisfy { $0.business.km < store.maxKm })
        XCTAssertEqual(all.first?.business.km, all.filter { $0.rank == all[0].rank }.map(\.business.km).min())
        XCTAssertEqual(store.business(sample.id)?.km ?? 99, Geo.km(nazareth, lat: sample.lat, lng: sample.lng), accuracy: 0.001)
        XCTAssertLessThan(store.business(sample.id)?.km ?? 99, 6)
    }

    func testAChosenTownIsUsedWhenThereIsNoPosition() {
        let store = Store()
        store.chooseTown("nazareth")
        XCTAssertFalse(store.isLive)
        XCTAssertEqual(store.here, "nazareth")
        XCTAssertEqual(store.origin.lat, store.places["nazareth"]!.lat, accuracy: 0.0001)
        XCTAssertTrue(store.near.allSatisfy { $0.km < store.maxKm })
        XCTAssertEqual(store.near.map(\.km), store.near.map(\.km).sorted())
        store.chooseTown("sakhnin")
    }

    func testAPositionOutsideTheAreaFallsBackToTheChosenTown() {
        let store = Store()
        store.chooseTown("sakhnin")
        // Eilat, far south of anything Darb covers
        store.stand(at: Coordinate(lat: 29.55, lng: 34.95))
        XCTAssertTrue(store.outside)
        XCTAssertFalse(store.isLive)
        XCTAssertEqual(store.here, "sakhnin")
        store.stand(at: nil)
    }

    func testTownSearchReadsAllThreeLanguages() {
        let store = Store()
        XCTAssertEqual(store.towns(matching: "כרמיאל").first?.slug, "karmiel")
        XCTAssertEqual(store.towns(matching: "كرميئيل").first?.slug, "karmiel")
        XCTAssertEqual(store.towns(matching: "karmiel").first?.slug, "karmiel")
        XCTAssertEqual(store.towns(matching: "").count, store.data.places.count)
    }

    func testTheWidgetMeasuresFromTheSameOrigin() throws {
        let data = try XCTUnwrap(Nearest.load())
        let d = UserDefaults(suiteName: "darb.tests.origin")!
        d.removePersistentDomain(forName: "darb.tests.origin")
        d.set("nazareth", forKey: "darbTown")
        XCTAssertEqual(Nearest.origin(in: data, defaults: d).place?.slug, "nazareth")
        d.set(karmiel.lat, forKey: "darbOriginLat"); d.set(karmiel.lng, forKey: "darbOriginLng")
        let o = Nearest.origin(in: data, defaults: d)
        XCTAssertEqual(o.place?.slug, "karmiel")
        let answers = Nearest.answers(in: data, from: o.point, at: .now)
        XCTAssertFalse(answers.isEmpty)
        XCTAssertTrue(answers.allSatisfy { $0.business.km < 30 })
    }
}

/// The language switch: copy, data, direction and typeface.
@MainActor
final class LanguageTests: XCTestCase {
    override func tearDown() { Lang.current = .he }

    func testDirectionAndTypefaceFollowTheLanguage() {
        XCTAssertTrue(Lang.he.isRTL); XCTAssertTrue(Lang.ar.isRTL); XCTAssertFalse(Lang.en.isRTL)
        XCTAssertEqual(Typeface.name(.bold, in: .he), "Heebo-Bold")
        XCTAssertEqual(Typeface.name(.heavy, in: .ar), "Cairo-ExtraBold")
        XCTAssertEqual(Typeface.name(.heavy, in: .en), "Ubuntu-Bold")
        // numbers are drawn in the language's own face
        XCTAssertEqual(Typeface.figure(.bold), Typeface.name(.bold))
    }

    func testEveryTypefaceIsInTheBundleWithItsLicence() {
        for name in Typeface.files {
            XCTAssertNotNil(UIFont(name: name, size: 12), "\(name) is not registered")
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "ttf"))
        }
        for licence in ["Heebo-OFL", "Cairo-OFL", "Ubuntu-UFL"] { XCTAssertNotNil(Bundle.main.url(forResource: licence, withExtension: "txt")) }
    }

    func testCopyChangesWithTheLanguage() {
        XCTAssertEqual(L("סגור", in: .he), "סגור")
        XCTAssertEqual(L("סגור", in: .ar), "مسكّر")
        XCTAssertEqual(L("סגור", in: .en), "Closed")
        XCTAssertEqual(L("פתוח עד %@", in: .en, "22:00"), "Open until 22:00")
        // the pieces of a phrase can change places between languages
        XCTAssertEqual(L("%lld מתוך %lld", in: .en, 2, 9), "2 of 9")
        XCTAssertEqual(L("web.contact.form.send", in: .ar), "ابعث")
    }

    func testTheStoreSwitchesLanguageAndTheDataFollows() throws {
        let store = Store()
        store.setLang(.ar)
        XCTAssertEqual(Lang.current, .ar)
        XCTAssertEqual(store.placeName("sakhnin"), "سخنين")
        XCTAssertEqual(store.kindName("restaurants"), "مطاعم")
        XCTAssertEqual(Need.byKey("fuel")?.title, "بنزين")
        let b = try XCTUnwrap(store.all.first { $0.names.ar != $0.names.he })
        XCTAssertEqual(b.name, b.names.ar)
        XCTAssertEqual(store.promo.plans.first?.title, "إدراج ببلاش")
        store.setLang(.en)
        XCTAssertEqual(store.placeName("sakhnin"), "Sakhnin")
        XCTAssertEqual(b.name, b.names.en)
        XCTAssertEqual(OpenHours.status(.unknown, at: .now).text, "No opening hours")
        store.setLang(.he)
        XCTAssertEqual(store.placeName("sakhnin"), "סח'נין")
    }

    func testThePhoneLanguageIsOnlyTheFirstGuess() {
        XCTAssertEqual(Lang.fromPhone(["ar-IL", "en-US"]), .ar)
        XCTAssertEqual(Lang.fromPhone(["en-GB"]), .en)
        XCTAssertEqual(Lang.fromPhone(["fr-FR", "he-IL"]), .he)
        XCTAssertEqual(Lang.fromPhone(["ru-RU"]), .he)
    }

    /// Every phrase the app can show exists in all three languages, with the same pieces to fill, and keeps the copy rules.
    func testTheCatalogIsCompleteAndKeepsTheCopyRules() throws {
        var keys: [String] = Need.all.flatMap { [$0.he, $0.pageTitle] } + ["מרקחת", "צפון", "דרום מערב", "ראשון", "שבת"]
        keys += DarbAPI.Inquiry.Topic.allCases.map { "web.contact.form.topics." + $0.rawValue }
        keys += ["web.landing.hero.title", "web.near.ask", "web.join.done.title", "web.messages.tagline", "ממומן"]
        let pieces = /%(?:\d\$)?(?:lld|@)/
        for key in keys {
            for lang in Lang.allCases {
                XCTAssertTrue(Strings.has(key, in: lang), "\(key) is missing in \(lang)")
                let text = Strings.text(key, in: lang)
                XCTAssertFalse(text.contains("–") || text.contains("—") || text.contains(" - "), "a dash in \(key) (\(lang))")
                XCTAssertEqual(text.matches(of: pieces).count, Strings.text(key, in: .he).matches(of: pieces).count, key)
            }
        }
        // "כשר" only as a word of its own: "כשרוצים" is a different word
        let off = OffCopy(#"חלאל|(?<![א-ת])כשר(?![א-ת])|حلال|halal|kosher|עברית|ערבית|אנגלית|hebrew|arabic"#)
        for lang in Lang.allCases {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"))
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path + "/Localizable.strings") as? [String: String])
            XCTAssertGreaterThan(table.count, 500)
            for (key, text) in table {
                XCTAssertFalse(off.isIn(text.lowercased()), "\(key) in \(lang): \(text)")
                XCTAssertFalse(text.contains("–") || text.contains("—"), "a dash in \(key) (\(lang))")
            }
        }
    }

    func testSearchReadsARequestInAnyOfTheThree() {
        let store = Store()
        XCTAssertEqual(store.parse("מוסך בשפרעם"), ParsedQuery(kind: "garages", place: "shefaram", text: ""))
        XCTAssertEqual(store.parse("pharmacy in Karmiel").kind, "pharmacies")
        XCTAssertEqual(store.parse("pharmacy in Karmiel").place, "karmiel")
        XCTAssertEqual(store.parse("صيدلية بكرميئيل").kind, "pharmacies")
        XCTAssertEqual(store.parse("صيدلية بكرميئيل").place, "karmiel")
        XCTAssertFalse(store.search("pizza").isEmpty)
    }
}

/// The words the app's copy never uses, as a pattern. "כשר" counts only as a word of its own: "כשרוצים" is another word.
struct OffCopy {
    private let regex: NSRegularExpression
    init(_ pattern: String) { regex = try! NSRegularExpression(pattern: pattern) }
    func isIn(_ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
}

/// The forms that post to the Darb API.
@MainActor
final class FormTests: XCTestCase {
    private func inquiry(name: String = "נור", contact: String = "050 123 4567", message: String = "שלום, יש לי שאלה על דרב.") -> DarbAPI.Inquiry {
        DarbAPI.Inquiry(name: name, contact: contact, businessName: nil, topic: .general, plan: nil, message: message, locale: "he")
    }

    func testTheContactFormKeepsTheContractRules() {
        XCTAssertTrue(inquiry().problems().isEmpty)
        XCTAssertTrue(inquiry(contact: "noor@example.com").problems().isEmpty)
        XCTAssertEqual(inquiry(name: "נ").problems(), [.name])
        XCTAssertEqual(inquiry(contact: "12345").problems(), [.contact])
        XCTAssertEqual(inquiry(contact: "not a contact").problems(), [.contact])
        XCTAssertEqual(inquiry(message: "קצר").problems(), [.messageShort])
        XCTAssertEqual(inquiry(message: String(repeating: "א", count: 3001)).problems(), [.messageLong])
    }

    func testTheInquiryIsSentAsTheApiReadsIt() throws {
        var i = inquiry()
        i.topic = .plan; i.plan = "spotlight"
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(i)) as? [String: Any])
        XCTAssertEqual(json["topic"] as? String, "plan")
        XCTAssertEqual(json["plan"] as? String, "spotlight")
        XCTAssertEqual(json["locale"] as? String, "he")
        XCTAssertNil(json["businessName"])
        XCTAssertNil(json["website"], "the honeypot is never sent")
    }

    func testTheJoinRequestIsSentAsTheApiReadsIt() throws {
        let j = DarbAPI.Join(name: ["ar": "مخبز"], kindSlug: "bakeries", placeSlug: "sakhnin", lat: 32.86, lng: 35.3, address: [:], phone: "+972 50-123-4567",
                             whatsapp: nil, website: nil, links: [:], hours: .init(weekly: ["0": [.init(open: "09:00", close: "18:00")]]), description: [:],
                             owner: .init(name: "سامر", phone: "050-1234567", email: nil), note: nil, locale: "ar")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(j)) as? [String: Any])
        XCTAssertEqual(json["source"] as? String, "manual")
        XCTAssertEqual((json["name"] as? [String: String])?["ar"], "مخبز")
        let hours = try XCTUnwrap(json["hours"] as? [String: Any])
        XCTAssertNotNil(hours["weekly"]); XCTAssertEqual((hours["exceptions"] as? [Any])?.count, 0)
        XCTAssertEqual((json["owner"] as? [String: Any])?["phone"] as? String, "050-1234567")
        XCTAssertTrue(DarbAPI.Check.joinPhone("+972 50-123-4567"))
        XCTAssertFalse(DarbAPI.Check.joinPhone("abc"))
        XCTAssertEqual(JoinForm.clock(1440), "24:00")
        XCTAssertEqual(JoinForm.clock(545), "09:05")
    }

    func testTheNavigationLinksCarryThePoint() {
        XCTAssertEqual(NavApp.waze.drive(lat: 32.9, lng: 35.3).absoluteString, "https://waze.com/ul?ll=32.9,35.3&navigate=yes")
        XCTAssertTrue(NavApp.apple.drive(lat: 32.9, lng: 35.3).absoluteString.contains("daddr=32.9,35.3"))
        XCTAssertTrue(NavApp.google.drive(lat: 32.9, lng: 35.3).absoluteString.hasPrefix("comgooglemaps://"))
    }
}

/// The valley's layout.
@MainActor
final class ValleyTests: XCTestCase {
    /// On the tall phone and the small one, with a short header and a tall one: the hills begin under the header,
    /// the names stand on the hills and never on each other, and no village is drawn on top of another.
    func testTheHeaderStandsOnCleanSkyAndNothingCollides() {
        let store = Store()
        store.chooseTown("sakhnin")
        let focus = store.firsts().compactMap(\.entry).first?.id
        for (size, header) in [(CGSize(width: 440, height: 315), CGFloat(182)), (CGSize(width: 440, height: 330), CGFloat(198)), (CGSize(width: 390, height: 280), CGFloat(152))] {
            let l = ValleyLayout(store: store, size: size, focus: focus, header: header)
            XCTAssertLessThanOrEqual(l.labels.count, ValleyLayout.maxLabels)
            XCTAssertLessThanOrEqual(l.villages.count, ValleyLayout.maxVillages)
            XCTAssertGreaterThan(l.villages.count, 5)
            // the far ridge never rises into the header
            for x in stride(from: CGFloat(0), through: size.width, by: 8) { XCTAssertGreaterThan(l.ridges.at(0, x), header + 8) }
            XCTAssertTrue(l.labels.allSatisfy { $0.p.y - 11 >= header + 10 && $0.p.y < size.height - 40 }, "\(l.labels.map(\.p))")
            for (i, a) in l.villages.enumerated() {
                XCTAssertGreaterThan(a.ground.minY, header)
                for b in l.villages[(i + 1)...] { XCTAssertFalse(a.ground.intersects(b.ground)) }
            }
            // a town with nobody open has no open house; one with anybody open has at least one
            for v in l.villages { XCTAssertEqual(v.houses.contains(where: \.open), v.share > 0) }
        }
    }
}

import Testing

@Suite struct WhatsAppNumbers {
    @Test func localNumbersGainTheCountryCode() {
        #expect(Outside.waDigits("054-722-7619") == "972547227619")
        #expect(Outside.waDigits("0547227619") == "972547227619")
        #expect(Outside.waDigits("+972 52-438-2229") == "972524382229")
        #expect(Outside.waDigits("+972 (0)52-438-2229") == "972524382229")
        #expect(Outside.waDigits("972504774367") == "972504774367")
        #expect(Outside.waDigits("547227619") == "972547227619")
    }
}
