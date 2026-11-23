import Foundation

/// The bundled data: every real business in the north, in three languages, written by scripts/export-data.py
/// from packages/seed/data. Nothing here is measured from any one town; distance is worked out on the phone.
struct DarbData: Sendable {
    /// The town the app stands in until the person chooses one or shares their location.
    let home: String
    let sectors: [Sector]
    let kinds: [Kind]
    let places: [Place]
    /// The distinct opening weeks; each business points at one.
    let weeks: [Hours]
    let businesses: [Business]

    init(home: String, sectors: [Sector], kinds: [Kind], places: [Place], weeks: [Hours] = [], businesses: [Business]) {
        self.home = home; self.sectors = sectors; self.kinds = kinds; self.places = places; self.weeks = weeks; self.businesses = businesses
    }
    /// Nothing yet: what the app holds for the moment before the bundled data has been read.
    static let empty = DarbData(home: "sakhnin", sectors: [], kinds: [], places: [], businesses: [])
}

struct Sector: Decodable, Sendable, Hashable, Identifiable {
    let slug: String
    let name: Tri
    let accent: String
    var id: String { slug }
}

struct Kind: Decodable, Sendable, Hashable, Identifiable {
    let slug: String
    let sector: String
    let name: Tri
    /// Other words people use for this kind, by language.
    let syn: [String: [String]]
    var id: String { slug }
    /// The kind's name in the language in use now.
    var title: String { name.now }
    /// Every word that means this kind, in every language.
    var words: [String] { [name.he, name.ar, name.en] + (syn["he"] ?? []) + (syn["ar"] ?? []) + (syn["en"] ?? []) }

    static func == (a: Kind, b: Kind) -> Bool { a.slug == b.slug }
    func hash(into h: inout Hasher) { h.combine(slug) }
}

struct Place: Decodable, Sendable, Hashable, Identifiable {
    let slug: String
    let name: Tri
    let aliases: [String]
    let lat: Double
    let lng: Double
    /// city, town, village or neighbourhood.
    let type: String
    var id: String { slug }
    /// The town's name in the language in use now, without the note some names carry in brackets.
    var title: String { Place.plain(name.now) }
    static func plain(_ s: String) -> String { s.replacingOccurrences(of: #"\s*\(.*?\)"#, with: "", options: .regularExpression) }

    static func == (a: Place, b: Place) -> Bool { a.slug == b.slug }
    func hash(into h: inout Hasher) { h.combine(slug) }
}

/// One business. What never changes about it is held once and shared; only the distance is its own.
/// So an array of thirteen thousand of them is copied, filtered and sorted at the cost of a pointer each.
struct Business: Sendable, Hashable, Identifiable {
    private final class Core: Sendable {
        let id: Int
        let names: Tri
        let kind: String
        let place: String
        let lat: Double
        let lng: Double
        let hours: Hours
        let week: Int
        let demoHours: Bool
        let tags: Tri?
        init(id: Int, names: Tri, kind: String, place: String, lat: Double, lng: Double, hours: Hours, week: Int, demoHours: Bool, tags: Tri?) {
            self.id = id; self.names = names; self.kind = kind; self.place = place; self.lat = lat; self.lng = lng
            self.hours = hours; self.week = week; self.demoHours = demoHours; self.tags = tags
        }
    }
    private let core: Core
    /// Straight-line distance from where the person is, in kilometres. Filled in on the phone.
    var km: Double

    init(id: Int, name: String, kind: String, place: String, lat: Double, lng: Double, km: Double, hours: Hours, demoHours: Bool, tag: String?) {
        self.init(id: id, names: Tri(name), kind: kind, place: place, lat: lat, lng: lng, km: km, hours: hours, demoHours: demoHours, tags: tag.map { Tri($0) })
    }
    init(id: Int, names: Tri, kind: String, place: String, lat: Double, lng: Double, km: Double = 0, hours: Hours, week: Int = -1, demoHours: Bool, tags: Tri?) {
        core = Core(id: id, names: names, kind: kind, place: place, lat: lat, lng: lng, hours: hours, week: week, demoHours: demoHours, tags: tags)
        self.km = km
    }

    var id: Int { core.id }
    var names: Tri { core.names }
    var kind: String { core.kind }
    var place: String { core.place }
    var lat: Double { core.lat }
    var lng: Double { core.lng }
    var hours: Hours { core.hours }
    /// Which of the distinct weeks this is, or -1 when the hours are the business's alone.
    var week: Int { core.week }
    /// The hours are not confirmed by the business: they are the usual week of its kind.
    var demoHours: Bool { core.demoHours }
    /// A line about the place from its source, when it has one.
    var tags: Tri? { core.tags }

    /// The name in the language in use now.
    var name: String { names.now }
    var tag: String? { tags?.now }
    /// Rough driving minutes from where the person is.
    var minutes: Int { Geo.minutes(km: km) }

    static func == (a: Business, b: Business) -> Bool { a.core.id == b.core.id }
    func hash(into h: inout Hasher) { h.combine(core.id) }
}

/// One open span of a day, in minutes from midnight. `close` may be smaller than `open` when it runs past midnight.
struct Span: Sendable, Equatable {
    let open: Int
    let close: Int
    let openText: String
    let closeText: String
}

enum Hours: Sendable, Equatable, Decodable {
    /// Spans per weekday, 0 is Sunday.
    case weekly([Int: [Span]])
    case appointment
    case unknown

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .unknown; return }
        if let s = try? c.decode(String.self) { self = s == "appt" ? .appointment : .unknown; return }
        let raw = try c.decode([String: [[String]]].self)
        var out: [Int: [Span]] = [:]
        for (day, spans) in raw {
            guard let d = Int(day) else { continue }
            out[d] = spans.compactMap { pair in
                guard pair.count == 2, let o = Hours.minutes(pair[0]), let z = Hours.minutes(pair[1]) else { return nil }
                return Span(open: o, close: z, openText: pair[0], closeText: pair[1])
            }
        }
        self = .weekly(out)
    }

    static func minutes(_ t: String) -> Int? {
        let p = t.split(separator: ":").compactMap { Int($0) }
        return p.count == 2 ? p[0] * 60 + p[1] : nil
    }
}

/// What a place's page adds to its listing. Read from details.json the first time a page needs it.
struct Extra: Decodable, Sendable {
    let phone: String?
    let addr: Tri?
    let web: String?
    let wa: String?
    let attr: Attributes?
    let links: Links?
}

struct Attributes: Decodable, Sendable {
    let bankCode: Int?
    let branchCode: Int?
    let fuelAdminNo: Int?
    let motGarageType: String?
    let motGarageId: Int?
    let eduSymbol: Int?
    let delivers: Bool?
    let takeaway: Bool?
    let wheelchair: Bool?
    let outdoorSeating: Bool?
    let vegan: Bool?
    let vegetarian: Bool?
}

struct Links: Decodable, Sendable {
    let instagram: String?
    let facebook: String?
    let tiktok: String?
}

/// Sample per-kind page content (menu, prices, services). Always shown as an example.
struct SampleScreen: Decodable, Sendable {
    let title: Tri
    let sub: Tri?
    let tags: [Tri]?
    /// Each item is a label and a line about it.
    let items: [[Tri]]
    let cta: Tri?
}

// MARK: reading the bundled files

extension DarbData {
    /// darb.json as it is written: the businesses are columns, one array per field.
    private struct File: Decodable {
        struct Columns: Decodable {
            let id: [Int]
            let kind: [Int]
            let place: [Int]
            let lat: [Double]
            let lng: [Double]
            let hours: [Int]
            let demo: [Int]
            let tag: [Int]
            let name: [String: [String]]
        }
        let home: String
        let sectors: [Sector]
        let kinds: [Kind]
        let places: [Place]
        let hours: [Hours]
        let tags: [String: [String]]
        let businesses: Columns
    }

    /// The live map from Darb's server when the app has fetched it (LiveData), otherwise the copy in the bundle.
    static func load(from bundle: Bundle = .main) -> DarbData? {
        if let url = LiveFiles.url("darb"), let raw = try? Data(contentsOf: url, options: .mappedIfSafe), let d = try? decode(raw) { return d }
        guard let url = bundle.url(forResource: "darb", withExtension: "json"), let raw = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? decode(raw)
    }

    static func decode(_ raw: Data) throws -> DarbData {
        let f = try JSONDecoder().decode(File.self, from: raw)
        let c = f.businesses
        let n = c.id.count
        guard c.kind.count == n, c.place.count == n, c.lat.count == n, c.lng.count == n, c.hours.count == n, c.demo.count == n, c.tag.count == n,
              let he = c.name["he"], let ar = c.name["ar"], let en = c.name["en"], he.count == n, ar.count == n, en.count == n,
              let tHe = f.tags["he"], let tAr = f.tags["ar"], let tEn = f.tags["en"]
        else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The business columns are not the same length.")) }
        // each distinct line about a place is built once and shared
        let tags: [Tri?] = tHe.indices.map { i in tHe[i].isEmpty ? nil : Tri(he: tHe[i], ar: tAr[i], en: tEn[i]) }
        var out: [Business] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let k = c.kind[i], p = c.place[i], w = c.hours[i]
            guard f.kinds.indices.contains(k), f.places.indices.contains(p) else { continue }
            out.append(Business(
                id: c.id[i], names: Tri(he: he[i], ar: ar[i], en: en[i]), kind: f.kinds[k].slug, place: f.places[p].slug,
                lat: c.lat[i], lng: c.lng[i],
                hours: f.hours.indices.contains(w) ? f.hours[w] : .unknown, week: f.hours.indices.contains(w) ? w : -1,
                demoHours: c.demo[i] == 1, tags: tags.indices.contains(c.tag[i]) ? tags[c.tag[i]] : nil))
        }
        return DarbData(home: f.home, sectors: f.sectors, kinds: f.kinds, places: f.places, weeks: f.hours, businesses: out)
    }

    static func details(from bundle: Bundle = .main) -> [Int: Extra] {
        guard let url = LiveFiles.url("details") ?? bundle.url(forResource: "details", withExtension: "json"), let raw = try? Data(contentsOf: url, options: .mappedIfSafe),
              let all = try? JSONDecoder().decode([String: Extra].self, from: raw) else { return [:] }
        var out: [Int: Extra] = [:]
        out.reserveCapacity(all.count)
        for (k, v) in all { if let id = Int(k) { out[id] = v } }
        return out
    }

    static func screens(from bundle: Bundle = .main) -> [String: SampleScreen] {
        guard let url = bundle.url(forResource: "screens", withExtension: "json"), let raw = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: SampleScreen].self, from: raw)) ?? [:]
    }
}

/// A point on the map.
struct Coordinate: Sendable, Hashable, Codable {
    let lat: Double
    let lng: Double
}

enum Geo {
    /// Kilometres between two points, straight. Good to a few metres across the north.
    static func km(_ a: Coordinate, lat: Double, lng: Double) -> Double {
        let kx = cos(a.lat * .pi / 180) * 111.32, ky = 111.2
        return hypot((lng - a.lng) * kx, (lat - a.lat) * ky)
    }
    static func km(_ a: Coordinate, _ b: Coordinate) -> Double { km(a, lat: b.lat, lng: b.lng) }
    static func meters(_ a: Business, _ b: Business) -> Double { km(Coordinate(lat: a.lat, lng: a.lng), lat: b.lat, lng: b.lng) * 1000 }
    /// Rough driving minutes for a straight-line distance.
    static func minutes(km: Double) -> Int { max(1, Int((km * 1.7 + 1).rounded())) }
    /// Rough walking minutes for a straight-line distance: streets wind, and people walk about 5 km an hour.
    static func walkMinutes(km: Double) -> Int { max(1, Int((km * 1.3 / 5 * 60).rounded())) }
    /// The bearing from one point to another: 0 is north, clockwise, in radians.
    static func bearing(from a: Coordinate, lat: Double, lng: Double) -> Double {
        atan2((lng - a.lng) * cos(a.lat * .pi / 180) * 111.32, (lat - a.lat) * 111.2)
    }
    /// The eight winds in plain words, for a bearing in radians.
    static func wind(_ bearing: Double) -> String {
        let names = ["צפון", "צפון מזרח", "מזרח", "דרום מזרח", "דרום", "דרום מערב", "מערב", "צפון מערב"]
        let turn = (bearing / (2 * .pi)).truncatingRemainder(dividingBy: 1)
        return L(names[Int(((turn < 0 ? turn + 1 : turn) * 8).rounded()) % 8])
    }
    /// A distance split into its number and its unit, for the big figures.
    static func distanceParts(_ km: Double) -> (value: String, unit: String) {
        km < 1 ? ("\(max(10, Int((km * 100).rounded()) * 10))", L("מ׳")) : (String(format: km < 10 ? "%.1f" : "%.0f", km), L("ק״מ"))
    }
    static func distance(_ km: Double) -> String {
        let p = distanceParts(km)
        return "\(p.value) \(p.unit)"
    }
}

/// Where the live map is kept once fetched from Darb's server: in the app group, so the widget and Siri read the
/// same businesses as the app. Each file is used only when it is there; until the first fetch, the bundle's are.
enum LiveFiles {
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.group)?
            .appendingPathComponent("Library/Caches/live", isDirectory: true)
    }
    static func url(_ name: String) -> URL? {
        guard let f = folder?.appendingPathComponent(name + ".json"), FileManager.default.fileExists(atPath: f.path) else { return nil }
        return f
    }
}
