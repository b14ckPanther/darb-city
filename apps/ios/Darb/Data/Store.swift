import SwiftUI

/// One place in a list, with its status at the store's moment.
struct Entry: Identifiable, Hashable, Sendable {
    let business: Business
    let status: Status
    /// Open now, but it will have closed by the time you get there.
    var late = false
    var id: Int { business.id }
    /// The order of answers: open and still open on arrival, then open but closing before you arrive,
    /// then by appointment, then closed.
    var rank: Int { status.isOpen ? (late ? 1 : 0) : status.rank + 1 }
    static func == (a: Entry, b: Entry) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// What a place page lists and how it looks.
struct PlaceQuery: Sendable {
    let title: String
    let color: Color
    let art: String
    let need: Need?
    /// The symbol to draw when there is no 3D object.
    var symbol: String = "mappin"
    let kinds: [String]
    /// A business to put first (from search).
    let pinned: Int?
}

/// How the app looks: by the hour (paper by day, ink by night), or always one of the two.
enum Appearance: String, CaseIterable, Sendable, Identifiable {
    case hour, light, dark
    var id: String { rawValue }
}

/// One town as the valley draws it: how many places it has within reach, how many are open, and where it lies.
struct TownStat: Sendable {
    let slug: String
    var n = 0
    var open = 0
    /// The sum of its places' bearings (as a share of half a turn, east positive) and distances; divide by `n`.
    var dir = 0.0
    var km = 0.0
}

/// Every distance from one point, worked out in one go and off the main thread when it can be.
struct Measured: Sendable {
    /// Every business, in the data's own order, with its distance from the point.
    let all: [Business]
    /// Those within driving distance, nearest first, and the same by kind.
    let near: [Business]
    let byKind: [String: [Business]]

    static func from(_ businesses: [Business], origin o: Coordinate, maxKm: Double) -> Measured {
        var all = businesses
        let kx = cos(o.lat * .pi / 180) * 111.32, ky = 111.2
        var near: [Business] = []
        near.reserveCapacity(all.count / 2)
        for i in all.indices {
            let km = hypot((all[i].lng - o.lng) * kx, (all[i].lat - o.lat) * ky)
            all[i].km = km
            if km < maxKm { near.append(all[i]) }
        }
        near.sort { $0.km < $1.km }
        return Measured(all: all, near: near, byKind: Dictionary(grouping: near, by: \.kind))
    }
}

@MainActor @Observable
final class Store {
    /// The bundled data. Empty for the first moment of a launch, until it has been read in the background.
    private(set) var data: DarbData
    /// The data has been read and measured, and the answers are real.
    private(set) var isReady = false
    let promo: Promo
    let location: LocationService
    private(set) var now: Date
    /// The language the app speaks. Changing it redraws everything.
    private(set) var lang: Lang
    private(set) var appearance: Appearance
    /// Places the person kept, newest first.
    private(set) var saved: [Int]
    /// Places with a "tell me when it opens" reminder waiting.
    private(set) var reminders: Set<Int>
    /// How often the person opened each need, by part of the day. Kept on this device only.
    private(set) var habits: [String: [String: Int]]
    /// The need the person chose for the lead card, by part of the day.
    private(set) var leadPicks: [String: String]
    /// How far "within driving distance" reaches, in kilometres.
    let maxKm = 30.0

    // MARK: where the person is

    /// The town the person chose to browse from. Used whenever their position is not.
    private(set) var town: String
    /// The person asked for answers from their real position.
    private(set) var followsLocation: Bool
    /// The point every distance is measured from: the person's position, or the chosen town's centre.
    private(set) var origin: Coordinate
    /// The town nearest to that point, for the header.
    private(set) var here: String
    /// The person's position is known but is outside the area Darb covers, so the chosen town is used.
    private(set) var outside = false
    /// Every place within driving distance of the origin, nearest first.
    private(set) var near: [Business] = []
    private(set) var openCount = 0
    private(set) var kindCount = 0
    /// The towns within reach, for the valley. Worked out once whenever the clock or the place changes.
    private(set) var townStats: [TownStat] = []
    /// What a place's page adds to its listing; read off the main thread soon after the app opens.
    private(set) var details: [Int: Extra]?
    private(set) var screens: [String: SampleScreen] = [:]

    @ObservationIgnored private(set) var kinds: [String: Kind] = [:]
    @ObservationIgnored private(set) var places: [String: Place] = [:]
    @ObservationIgnored private(set) var sectors: [String: Sector] = [:]
    /// Every business, with its distance from the origin filled in.
    @ObservationIgnored private(set) var all: [Business] = []
    @ObservationIgnored private var index: [Int: Int] = [:]
    @ObservationIgnored private var nearByKind: [String: [Business]] = [:]
    @ObservationIgnored private var pulseCache: [String: NeedPulse] = [:]
    /// The status of each distinct week at this minute, and the minutes it has left when it is open and will close.
    @ObservationIgnored private var weekStatus: [Status] = []
    @ObservationIgnored private var weekLeft: [Int?] = []
    @ObservationIgnored private var firstsCache: [(need: Need, entry: Entry?)]?
    @ObservationIgnored var searchIndex: SearchIndex?
    @ObservationIgnored private var profiles: [Int: BusinessProfile] = [:]
    @ObservationIgnored private var sponsorships: [Sponsorship] = []
    /// Testing arguments that show what is not in the data yet, always marked as a demo:
    /// `-darbDemoMedia YES` draws placeholder logos, covers, photos and storefronts;
    /// `-darbDemoProfile all` (or a listing id) puts listings on a paid plan with the sample pages;
    /// `-darbDemoSponsor YES` fills the paid placements with nearby listings.
    @ObservationIgnored private let demoMedia = UserDefaults.standard.bool(forKey: "darbDemoMedia")
    @ObservationIgnored private let demoPaid = UserDefaults.standard.string(forKey: "darbDemoProfile")
    @ObservationIgnored private let demoSponsor = UserDefaults.standard.bool(forKey: "darbDemoSponsor")
    @ObservationIgnored private var arts: [Int: ArtRef] = [:]
    /// `-darbLocation 32.919,35.295` stands the person at a point, for screenshots and tests.
    @ObservationIgnored private var pinned: Coordinate?
    /// The point the distances are being measured from, which the origin follows a moment later when the
    /// measuring is done in the background; and a count that lets a newer measure overtake an older one.
    @ObservationIgnored private var aim: Coordinate
    @ObservationIgnored private var generation = 0

    static let remembered = ["darbSaved", "darbReminders", "darbHabits", "darbLeadPicks", "darbEventCounts", "darbEventsPending",
                             "darbOnboarded", "darbAppearance", "darbNavApp"]
    static let rememberedShared = ["darbLang", "darbTown", "darbFollowsLocation", "darbOriginLat", "darbOriginLng"]

    /// - Parameters:
    ///   - data: a small set of places for a test; nil reads the bundled data.
    ///   - background: read and measure the bundled data off the main thread, and show the app meanwhile.
    ///     The app starts this way. A test does not, so it can ask its questions straight away.
    init(data preset: DarbData? = nil, background: Bool = false) {
        promo = Bundle.main.url(forResource: "promo", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Promo.self, from: $0) } ?? .empty
        let moment = Store.clockNow()
        now = moment
        location = LocationService()
        // `-darbReset YES` forgets what this device remembers: language, town, kept places, reminders, habits, choices and counts
        if UserDefaults.standard.bool(forKey: "darbReset") {
            for key in Store.remembered { UserDefaults.standard.removeObject(forKey: key) }
            for key in Store.rememberedShared { Shared.defaults.removeObject(forKey: key) }
            Lang.reload()
        }
        lang = Lang.current
        appearance = UserDefaults.standard.string(forKey: "darbAppearance").flatMap(Appearance.init(rawValue:)) ?? .hour
        saved = (UserDefaults.standard.array(forKey: "darbSaved") as? [Int]) ?? []
        reminders = Set((UserDefaults.standard.array(forKey: "darbReminders") as? [Int]) ?? [])
        habits = (UserDefaults.standard.dictionary(forKey: "darbHabits") as? [String: [String: Int]]) ?? [:]
        // `-darbLead bank` sets the lead card's need for this part of the day, for testing
        var picks = (UserDefaults.standard.dictionary(forKey: "darbLeadPicks") as? [String: String]) ?? [:]
        if let k = UserDefaults.standard.string(forKey: "darbLead"), Need.byKey(k) != nil { picks[Need.part(hour: Calendar.current.component(.hour, from: moment))] = k }
        leadPicks = picks
        profiles = Dictionary(promo.profiles.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        sponsorships = promo.sponsorships

        // `-darbTown karmiel` stands the app in a town for one run
        let bundled = preset == nil
        let once = bundled ? UserDefaults.standard.string(forKey: "darbTownOnce") : nil
        let chosen = once ?? (bundled ? Shared.defaults.string(forKey: "darbTown") : nil) ?? preset?.home ?? DarbData.empty.home
        town = chosen
        here = chosen
        followsLocation = bundled && once == nil ? (Shared.defaults.object(forKey: "darbFollowsLocation") as? Bool ?? false) : false
        // until the data is in, the last point the app measured from stands in
        let last = bundled && Shared.defaults.object(forKey: "darbOriginLat") != nil
            ? Coordinate(lat: Shared.defaults.double(forKey: "darbOriginLat"), lng: Shared.defaults.double(forKey: "darbOriginLng"))
            : Coordinate(lat: 32.8638, lng: 35.3023)
        origin = last
        aim = last
        if bundled, let raw = UserDefaults.standard.string(forKey: "darbLocation") {
            let p = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if p.count == 2 { pinned = Coordinate(lat: p[0], lng: p[1]) }
        }
        data = .empty
        location.onChange = { [weak self] in self?.place(background: true) }

        if let preset {
            install(preset, measured: nil)
            details = [:]
        } else if !background {
            guard let decoded = Perf.time("data.decode", { DarbData.load() }) else { fatalError("The bundled Darb data is missing or unreadable.") }
            install(decoded, measured: nil)
            Task.detached(priority: .userInitiated) { [weak self] in await self?.readTheRest(decoded) }
        } else {
            let start = (town: chosen, pinned: pinned, maxKm: maxKm)
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let decoded = Perf.time("data.decode", { DarbData.load() }) else { fatalError("The bundled Darb data is missing or unreadable.") }
                // the first measure is done here too, from the town the app will stand in
                let centre = (decoded.places.first { $0.slug == start.town } ?? decoded.places.first { $0.slug == decoded.home }).map { Coordinate(lat: $0.lat, lng: $0.lng) }
                let first = (start.pinned ?? centre).map { o in Perf.time("store.measure") { (origin: o, result: Measured.from(decoded.businesses, origin: o, maxKm: start.maxKm)) } }
                await MainActor.run { self?.install(decoded, measured: first) }
                await self?.readTheRest(decoded)
            }
        }
    }

    /// Takes the data in: the look-up tables, the first distances, who is open.
    private func install(_ decoded: DarbData, measured first: (origin: Coordinate, result: Measured)?) {
        Perf.time("store.install") {
            data = decoded
            kinds = Dictionary(decoded.kinds.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
            places = Dictionary(decoded.places.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
            sectors = Dictionary(decoded.sectors.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
            all = decoded.businesses
            index = Dictionary(decoded.businesses.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
            if places[town] == nil { town = places[decoded.home] != nil ? decoded.home : decoded.places.first?.slug ?? "" }
            isReady = true
            let target = whereToStand()
            outside = target.outside
            here = target.name
            aim = target.point
            if let first, Geo.km(first.origin, target.point) < 0.001 {
                apply(first.result, origin: first.origin)
            } else {
                apply(Perf.time("store.measure") { Measured.from(all, origin: target.point, maxKm: maxKm) }, origin: target.point)
            }
            if followsLocation { location.start() }
        }
    }

    /// The parts of the data no first screen needs: a place page's details, the sample pages, the search index.
    private nonisolated func readTheRest(_ decoded: DarbData, replacing: Bool = false) async {
        let d = Perf.time("data.details") { DarbData.details() }, s = DarbData.screens()
        await MainActor.run { self.details = d; self.screens = s }
        let built = Perf.time("search.index") { SearchIndex(decoded) }
        await MainActor.run { if replacing || self.searchIndex == nil { self.searchIndex = built } }
    }

    /// Takes in a newer map from Darb's server (LiveData): new and edited businesses show at once, measured from
    /// where the person stands, and the search learns them.
    func adopt(_ decoded: DarbData) {
        install(decoded, measured: nil)
        refresh()
        Task.detached(priority: .utility) { [weak self] in await self?.readTheRest(decoded, replacing: true) }
    }

    /// The current moment; `-darbTime 20:30` fixes the clock for screenshots and tests.
    static func clockNow() -> Date {
        guard let t = UserDefaults.standard.string(forKey: "darbTime"), let m = Hours.minutes(t) else { return .now }
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
    }

    /// Reads the clock again and works out who is open. There are a few hundred distinct weeks among
    /// thirteen thousand businesses, so everything about the hour is worked out once per week and shared.
    func refresh() {
        Perf.time("store.refresh") {
            now = Store.clockNow()
            weekStatus = data.weeks.map { OpenHours.status($0, at: now) }
            weekLeft = data.weeks.indices.map { weekStatus[$0].isOpen ? OpenHours.minutesLeft(data.weeks[$0], at: now) : nil }
            firstsCache = nil
            pulseCache = [:]
            // one pass over the places within reach: how many are open, and each town's share
            var open = 0
            var towns: [String: TownStat] = [:]
            for b in near {
                let isOpen = status(b).isOpen
                if isOpen { open += 1 }
                var t = towns[b.place] ?? TownStat(slug: b.place)
                t.n += 1
                if isOpen { t.open += 1 }
                t.dir += Geo.bearing(from: origin, lat: b.lat, lng: b.lng) / .pi
                t.km += b.km
                towns[b.place] = t
            }
            openCount = open
            townStats = towns.values.sorted { ($0.n, $0.slug) > ($1.n, $1.slug) }
        }
    }

    var hour: Int { Calendar.current.component(.hour, from: now) }
    var minuteOfDay: Int { OpenHours.minuteOfDay(now) }
    /// Whether it is day by the clock.
    var isDaytime: Bool { (6..<18).contains(hour) }
    /// Whether the app is drawn as day: by the clock, unless the person fixed the look.
    var looksDay: Bool { appearance == .hour ? isDaytime : appearance == .light }
    /// The name of the town the answers are measured from.
    var homeName: String { placeName(here) }
    /// The answers are measured from the person's real position right now.
    var isLive: Bool { (followsLocation || pinned != nil) && !outside && livePoint != nil }

    /// Minutes until a place that is open now closes; nil when it never does.
    private func minutesLeft(_ b: Business) -> Int? {
        weekLeft.indices.contains(b.week) ? weekLeft[b.week] : OpenHours.minutesLeft(b.hours, at: now)
    }

    func status(_ b: Business) -> Status {
        weekStatus.indices.contains(b.week) ? weekStatus[b.week] : OpenHours.status(b.hours, at: now)
    }
    func business(_ id: Int) -> Business? { index[id].map { all[$0] } }
    func placeName(_ slug: String) -> String { places[slug]?.title ?? (isReady ? slug : "") }
    func kindName(_ slug: String) -> String { kinds[slug]?.title ?? "" }
    func sector(ofKind slug: String) -> Sector? { kinds[slug].flatMap { sectors[$0.sector] } }
    func extra(_ id: Int) -> Extra? { details?[id] }

    // MARK: language and look

    func setLang(_ l: Lang) {
        Lang.current = l
        guard l != lang else { return }
        lang = l
        // a placeholder logo carries the first letter of the name, which changes with the language
        arts = [:]
        refresh()
    }

    func setAppearance(_ a: Appearance) {
        appearance = a
        UserDefaults.standard.set(a.rawValue, forKey: "darbAppearance")
    }

    // MARK: town and position

    private var livePoint: Coordinate? { pinned ?? location.coordinate }

    /// The person chose a town to browse from. Their position is no longer followed.
    func chooseTown(_ slug: String) {
        guard places[slug] != nil else { return }
        town = slug
        followsLocation = false
        pinned = nil
        Shared.defaults.set(slug, forKey: "darbTown")
        Shared.defaults.set(false, forKey: "darbFollowsLocation")
        location.stop()
        place(force: true)
    }

    /// The person asked for answers from where they are. Asks for permission the first time.
    func followLocation() {
        followsLocation = true
        Shared.defaults.set(true, forKey: "darbFollowsLocation")
        location.start()
        place(force: true)
    }

    /// Stands the person at a point, as the phone's position would. For tests.
    func stand(at point: Coordinate?) {
        pinned = point
        place(force: true)
    }

    /// Whether Darb has anything within reach of a point.
    func covers(_ c: Coordinate) -> Bool { data.places.contains { Geo.km(c, lat: $0.lat, lng: $0.lng) < 15 } }

    func nearestPlace(to c: Coordinate) -> Place? {
        data.places.min { Geo.km(c, lat: $0.lat, lng: $0.lng) < Geo.km(c, lat: $1.lat, lng: $1.lng) }
    }

    /// Where the app should stand now: the person's position when it is followed and inside the area, else the chosen town.
    private func whereToStand() -> (point: Coordinate, outside: Bool, name: String) {
        let centre = places[town].map { Coordinate(lat: $0.lat, lng: $0.lng) } ?? aim
        if followsLocation || pinned != nil, let live = livePoint {
            if covers(live) { return (live, false, nearestPlace(to: live)?.slug ?? town) }
            return (centre, true, town)
        }
        return (centre, false, town)
    }

    /// Works out the origin, and every distance from it. Called when the town, the permission or the position changes.
    /// - Parameter background: measure off the main thread and publish the result once. The position arriving from
    ///   the phone does this; a town the person just chose is measured on the spot, so the answer is there at once.
    private func place(force: Bool = false, background: Bool = false) {
        guard isReady else { return }
        let target = whereToStand()
        // a few steps do not change any answer
        guard force || target.outside != outside || Geo.km(aim, target.point) > 0.12 else { return }
        outside = target.outside
        here = target.name
        aim = target.point
        generation += 1
        guard background else { return apply(Perf.time("store.measure") { Measured.from(all, origin: target.point, maxKm: maxKm) }, origin: target.point) }
        let turn = generation, businesses = all, reach = maxKm
        Task.detached(priority: .userInitiated) { [weak self] in
            let m = Perf.time("store.measure") { Measured.from(businesses, origin: target.point, maxKm: reach) }
            await MainActor.run {
                // a newer position has been asked for since: this one is already out of date
                guard let self, self.generation == turn else { return }
                self.apply(m, origin: target.point)
            }
        }
    }

    /// Publishes a measure: the distances, what is near, and who of those is open.
    private func apply(_ m: Measured, origin point: Coordinate) {
        origin = point
        all = m.all
        nearByKind = m.byKind
        kindCount = m.byKind.count
        near = m.near
        Shared.defaults.set(point.lat, forKey: "darbOriginLat")
        Shared.defaults.set(point.lng, forKey: "darbOriginLng")
        if demoSponsor {
            // the second nearest of a few needs stands in for a paying business
            sponsorships = promo.sponsorships
            for key in ["food", "fuel", "coffee", "pharmacy"] {
                guard let n = Need.byKey(key) else { continue }
                let list = n.kinds.flatMap { nearByKind[$0] ?? [] }.sorted { $0.km < $1.km }
                if list.count > 1 { sponsorships.append(Sponsorship(business: list[1].id, plan: "spotlight", slots: [.home, .page], area: nil, demo: true)) }
            }
        }
        refresh()
    }

    // MARK: answers

    /// Places of these kinds within driving distance: open first, then nearest.
    func entries(kinds ks: [String], pinned: Int? = nil) -> [Entry] {
        Perf.time("store.entries") {
            var out: [Entry] = []
            for k in Set(ks) { for b in nearByKind[k] ?? [] where b.id != pinned { out.append(entry(b)) } }
            out.sort { ($0.rank, $0.business.km) < ($1.rank, $1.business.km) }
            if let p = pinned, let b = business(p) { out.insert(entry(b), at: 0) }
            return out
        }
    }

    /// The first of those, without sorting the rest.
    func best(kinds ks: [String]) -> Entry? {
        var best: Entry?
        for k in Set(ks) {
            for b in nearByKind[k] ?? [] {
                let e = entry(b)
                if best == nil || (e.rank, b.km) < (best!.rank, best!.business.km) { best = e }
            }
        }
        return best
    }

    func query(_ r: Route) -> PlaceQuery? {
        switch r {
        case .need(let k):
            guard let n = Need.byKey(k) else { return nil }
            return PlaceQuery(title: n.title, color: n.color, art: n.art, need: n, kinds: n.kinds, pinned: nil)
        case .kind(let slug):
            guard kinds[slug] != nil else { return nil }
            if let n = Need.forKind(slug) {
                return PlaceQuery(title: kindName(slug), color: n.color, art: n.art, need: n, kinds: [slug], pinned: nil)
            }
            let accent = sector(ofKind: slug).map { Color(hexString: $0.accent) } ?? .accentColor
            let symbol = ArtResolver.symbol(kind: slug) ?? sector(ofKind: slug)?.symbol ?? "mappin"
            return PlaceQuery(title: kindName(slug), color: accent, art: "", need: nil, symbol: symbol, kinds: [slug], pinned: nil)
        case .business(let id):
            guard let b = business(id), let q = query(.kind(b.kind)) else { return nil }
            return PlaceQuery(title: q.title, color: q.color, art: q.art, need: q.need, symbol: q.symbol, kinds: q.kinds, pinned: id)
        }
    }

    /// Kind counts by sector, for the "everything else" screen.
    func sectorCounts() -> [(sector: Sector, count: Int)] {
        var c: [String: Int] = [:]
        for (kind, list) in nearByKind { if let k = kinds[kind] { c[k.sector, default: 0] += list.count } }
        return data.sectors.compactMap { s in c[s.slug].map { (s, $0) } }.sorted { $0.count > $1.count }
    }
    func kindCounts(sector: String) -> [(kind: Kind, count: Int)] {
        data.kinds.filter { $0.sector == sector }.compactMap { k in nearByKind[k.slug].map { (k, $0.count) } }.sorted { $0.count > $1.count }
    }

    // MARK: what a place looks like and says about itself

    /// The picture for a business, resolved once: its cuisine, its name, its kind, its need, or a symbol.
    /// The object a need's tile and its page both show: the answer's own object (an ice cream for an ice cream
    /// shop), or the need's when the answer has none. One rule for both, so the page grows out of the tile unchanged.
    func answerArt(_ need: Need, _ entry: Entry?) -> String {
        guard let e = entry else { return need.art }
        return art(for: e.business).render ?? need.art
    }

    func art(for b: Business) -> ArtRef {
        if let a = arts[b.id] { return a }
        var a = ArtResolver.resolve(b, need: Need.forKind(b.kind), sector: sector(ofKind: b.kind)) { Store.hasArt($0) }
        // a business's own logo comes before any object: free for every business, whenever the data has one
        a.logo = profile(b.id)?.logo ?? b.logo
        a.initial = String(b.name.trimmingCharacters(in: .punctuationCharacters).prefix(1))
        arts[b.id] = a
        return a
    }

    /// Whether a render of this name is in the bundle.
    static func hasArt(_ name: String) -> Bool { ArtLibrary.shared.still(name) != nil }

    /// A place with its status now, and whether it will still be open after the drive there.
    func entry(_ b: Business) -> Entry {
        let s = status(b)
        guard s.isOpen else { return Entry(business: b, status: s) }
        // how long the place stays open is known per week, so nothing about its hours is worked out again here
        if weekLeft.indices.contains(b.week) { return Entry(business: b, status: s, late: weekLeft[b.week].map { $0 <= b.minutes } ?? false) }
        return Entry(business: b, status: s, late: !OpenHours.openOnArrival(b.hours, at: now, drive: b.minutes))
    }

    /// The status in full: when a place is closed for the rest of today, it also says when it opens next;
    /// when it will close before you can get there, it says that plainly.
    func statusLine(_ e: Entry) -> String {
        if e.late, let left = OpenHours.minutesLeft(e.business.hours, at: now) {
            return L("נסגר בעוד %lld דק׳, הנסיעה %lld", left, e.business.minutes)
        }
        guard e.status.state == .closed, e.status.closedForToday, let next = OpenHours.nextOpening(e.business.hours, after: now) else { return e.status.text }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: next)).day ?? 0
        let clock = OpenHours.clock(OpenHours.minuteOfDay(next))
        if days == 1 { return L("סגור, נפתח מחר ב %@", clock) }
        return L("סגור, נפתח ביום %@ ב %@", OpenHours.dayName(OpenHours.weekday(next)), clock)
    }

    /// One line on what a place is and where: the source's own description, else the kind.
    func tagline(_ b: Business) -> String {
        let town = placeName(b.place)
        var what = (b.tag ?? "").replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "24/7", with: L("24 שעות"))
        if what.isEmpty { what = kindName(b.kind) }
        return what.contains(town) || what.contains(town.replacingOccurrences(of: "-", with: " ")) ? what : "\(what) · \(town)"
    }

    // MARK: profiles and paid placements

    /// A testing argument is filling the app with stand-ins; the home screen says so.
    var isDemo: Bool { demoMedia || demoPaid != nil || demoSponsor }

    /// What a business shows beyond its bare listing, or nil for a listing with nothing more.
    func profile(_ id: Int) -> BusinessProfile? {
        var p = profiles[id]
        if p == nil, demoMedia || demoPaid == "all" || demoPaid == String(id) {
            p = .stand(for: id, plan: demoPaid == "all" || demoPaid == String(id) ? "spotlight" : "presence")
        }
        return demoMedia ? p?.withPlaceholders() : p
    }

    func isPaid(_ p: BusinessProfile?) -> Bool {
        guard let p else { return false }
        return promo.plans.first { $0.slug == p.plan }?.isPaid ?? false
    }

    private func entry(for s: Sponsorship) -> Entry? {
        guard let b = business(s.business), b.km < maxKm, promo.plans.first(where: { $0.slug == s.plan })?.isPaid ?? false else { return nil }
        if let area = s.area, !area.isEmpty, !area.contains(b.place), !area.contains(here) { return nil }
        return entry(b)
    }

    /// The paid placement on the home screen now. The sponsors in the area take turns, a few minutes each.
    var homeSponsor: (sponsorship: Sponsorship, entry: Entry)? {
        let live = sponsorships.filter { $0.slots.contains(.home) }.compactMap { s in entry(for: s).map { (s, $0) } }
        return live.isEmpty ? nil : live[(minuteOfDay / 3) % live.count]
    }

    /// The paid placement on a need's or a kind's page: a sponsor of that kind, and only one at most a few
    /// minutes further than the nearest place, so it is still a useful answer. It is shown beside the ranked places,
    /// labelled, and never moves or replaces any of them.
    func pageSponsor(kinds: [String], nearest: Entry?) -> (sponsorship: Sponsorship, entry: Entry)? {
        guard let nearest else { return nil }
        let live = sponsorships.filter { $0.slots.contains(.page) }.compactMap { s in entry(for: s).map { (s, $0) } }
            .filter { kinds.contains($0.1.business.kind) && $0.1.id != nearest.id && $0.1.business.minutes - nearest.business.minutes <= Sponsorship.pageDetour }
        return live.isEmpty ? nil : live[(minuteOfDay / 3) % live.count]
    }

    /// The lowest monthly price of a paid plan, for the invitation in an empty slot.
    var paidFrom: Int? { promo.plans.compactMap(\.monthly).filter { $0 > 0 }.min() }

    // MARK: kept places and reminders

    func isSaved(_ id: Int) -> Bool { saved.contains(id) }
    func toggleSaved(_ id: Int) {
        if let i = saved.firstIndex(of: id) { saved.remove(at: i) } else { saved.insert(id, at: 0) }
        UserDefaults.standard.set(saved, forKey: "darbSaved")
    }
    var savedEntries: [Entry] { saved.compactMap(business).map(entry) }

    func hasReminder(_ id: Int) -> Bool { reminders.contains(id) }
    func setReminder(_ id: Int, on: Bool) {
        if on { reminders.insert(id) } else { reminders.remove(id) }
        UserDefaults.standard.set(Array(reminders), forKey: "darbReminders")
    }

    // MARK: the lead card

    /// Why the lead card answers the need it does.
    enum LeadReason { case hour, habit, choice }

    /// The lead card's need: the one the person chose for this part of the day, else the one they open most at this
    /// time, else the hour's own order. Only the person's behaviour moves it; a paid placement never does.
    func lead(among firsts: [(need: Need, entry: Entry?)]) -> (need: Need, entry: Entry?, reason: LeadReason) {
        let part = Need.part(hour: hour)
        if let k = leadPicks[part], let f = firsts.first(where: { $0.need.key == k }) { return (f.need, f.entry, .choice) }
        let counts = habits[part] ?? [:]
        if let top = firsts.filter({ (counts[$0.need.key] ?? 0) >= 2 }).max(by: { counts[$0.need.key]! < counts[$1.need.key]! }) {
            return (top.need, top.entry, .habit)
        }
        let f = firsts.first { $0.entry?.status.isOpen == true } ?? firsts[0]
        return (f.need, f.entry, .hour)
    }

    /// The person opened a need's page: remember it for this part of the day.
    func noteOpened(need key: String) {
        // a screen opened by a testing argument is not the person's own choice
        guard UserDefaults.standard.string(forKey: "darbRoute") == nil else { return }
        let part = Need.part(hour: hour)
        habits[part, default: [:]][key, default: 0] += 1
        UserDefaults.standard.set(habits, forKey: "darbHabits")
    }

    /// The person chose what the lead card answers; nil goes back to choosing by habit and hour.
    func setLead(_ key: String?) {
        leadPicks[Need.part(hour: hour)] = key
        UserDefaults.standard.set(leadPicks, forKey: "darbLeadPicks")
    }

    /// The nearest open place for each everyday need, in the hour's order.
    /// A need's pulse right now, within driving distance: how many of its places are open, and the latest any of
    /// them stays open tonight. Worked out once a minute.
    func pulse(_ need: Need) -> NeedPulse {
        if let p = pulseCache[need.key] { return p }
        var open = 0, total = 0, allDay = false, latest = -1
        for k in need.kinds {
            for b in nearByKind[k] ?? [] {
                total += 1
                let s = status(b)
                guard s.isOpen else { continue }
                open += 1
                if let left = minutesLeft(b) { latest = max(latest, left) } else { allDay = true }
            }
        }
        let p = NeedPulse(open: open, total: total, allDay: allDay, latest: latest < 0 ? nil : (minuteOfDay + latest) % 1440)
        pulseCache[need.key] = p
        return p
    }

    func firsts() -> [(need: Need, entry: Entry?)] {
        if let f = firstsCache { return f }
        let f = Perf.time("store.firsts") { Need.order(hour: hour).compactMap(Need.byKey).map { (need: $0, entry: best(kinds: $0.kinds)) } }
        if isReady { firstsCache = f }
        return f
    }

    func nearestParking(to b: Business) -> (Business, Double)? {
        (nearByKind["parking"] ?? []).map { ($0, Geo.meters(b, $0)) }.min { $0.1 < $1.1 }
    }

    /// The bearing from where the person is to a business.
    func bearing(to b: Business) -> Double { Geo.bearing(from: origin, lat: b.lat, lng: b.lng) }

    // MARK: every town

    /// Towns for the town picker: all of them, nearest to the origin first, or those matching what was typed.
    func towns(matching text: String) -> [Place] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = q.isEmpty ? data.places : data.places.filter { p in
            p.name.searchKey.contains(q) || p.aliases.contains { $0.lowercased().contains(q) }
        }
        return pool.sorted { Geo.km(origin, lat: $0.lat, lng: $0.lng) < Geo.km(origin, lat: $1.lat, lng: $1.lng) }
    }
}

/// How alive a need is right now, around the person.
struct NeedPulse: Equatable, Sendable {
    let open: Int
    let total: Int
    /// Some place of this need never closes.
    let allDay: Bool
    /// The latest closing time among the open ones tonight, in minutes from midnight.
    let latest: Int?
}
