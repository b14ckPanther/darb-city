import Foundation

/// The nearest place open now for each everyday need, worked out straight from the bundled data.
/// The widget and Siri use this; it needs nothing from the app's screens.
enum Nearest {
    struct Answer: Sendable, Identifiable {
        let need: Need
        let business: Business
        let status: Status
        var id: String { need.key }
    }

    private static func rank(_ b: Business, _ s: Status, _ date: Date, _ calendar: Calendar) -> Int {
        s.isOpen ? (OpenHours.openOnArrival(b.hours, at: date, drive: b.minutes, calendar: calendar) ? 0 : 1) : s.rank + 1
    }

    /// The logos businesses have given, by listing id. Empty today: no business in the data has one yet.
    static func logos(from bundle: Bundle = .main) -> [Int: String] {
        guard let url = bundle.url(forResource: "promo", withExtension: "json"), let raw = try? Data(contentsOf: url),
              let promo = try? JSONDecoder().decode(Promo.self, from: raw) else { return [:] }
        return Dictionary(promo.profiles.compactMap { p in p.logo.map { (p.id, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// The places of the nine everyday needs only (needs.json): a third of the data, which is all the widget and Siri
    /// ask about, and light enough for a widget to read.
    static func load(from bundle: Bundle = .main) -> DarbData? {
        if let url = LiveFiles.url("needs"), let raw = try? Data(contentsOf: url, options: .mappedIfSafe), let d = try? DarbData.decode(raw) { return d }
        guard let url = bundle.url(forResource: "needs", withExtension: "json"), let raw = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? DarbData.decode(raw)
    }

    /// Where the app last measured from: the person's position, or the centre of the town they chose.
    /// The app writes it down for the widget and Siri, which do not ask for the position themselves.
    static func origin(in data: DarbData, defaults: UserDefaults = Shared.defaults) -> (point: Coordinate, place: Place?) {
        let town = defaults.string(forKey: "darbTown") ?? data.home
        let chosen = data.places.first { $0.slug == town } ?? data.places.first { $0.slug == data.home }
        var point = chosen.map { Coordinate(lat: $0.lat, lng: $0.lng) } ?? Coordinate(lat: 32.8638, lng: 35.3023)
        if defaults.object(forKey: "darbOriginLat") != nil {
            point = Coordinate(lat: defaults.double(forKey: "darbOriginLat"), lng: defaults.double(forKey: "darbOriginLng"))
        }
        let nearest = data.places.min { Geo.km(point, lat: $0.lat, lng: $0.lng) < Geo.km(point, lat: $1.lat, lng: $1.lng) }
        return (point, nearest ?? chosen)
    }

    /// One answer per need, in the order that suits the hour: open first, then nearest to `origin`.
    /// With no origin, the distances already on the businesses are used as they are.
    static func answers(in data: DarbData, from origin: Coordinate? = nil, at date: Date, maxKm: Double = 30, calendar: Calendar = .current) -> [Answer] {
        let hour = calendar.component(.hour, from: date)
        var statuses: [Int: Status] = [:]
        return Need.order(hour: hour).compactMap(Need.byKey).compactMap { need in
            let kinds = Set(need.kinds)
            var best: (b: Business, s: Status, rank: Int)?
            for var b in data.businesses where kinds.contains(b.kind) {
                if let origin { b.km = Geo.km(origin, lat: b.lat, lng: b.lng) }
                guard b.km < maxKm else { continue }
                let s: Status
                if b.week >= 0, let known = statuses[b.week] { s = known } else {
                    s = OpenHours.status(b.hours, at: date, calendar: calendar)
                    if b.week >= 0 { statuses[b.week] = s }
                }
                // the same order as in the app: a place that closes before you can get there comes after one that stays open
                let r = rank(b, s, date, calendar)
                if best == nil || (r, b.km) < (best!.rank, best!.b.km) { best = (b, s, r) }
            }
            return best.map { Answer(need: need, business: $0.b, status: $0.s) }
        }
    }
}
