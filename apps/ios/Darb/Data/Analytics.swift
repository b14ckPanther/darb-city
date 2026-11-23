import Foundation

/// What people did with a business, counted on the device.
/// This stands in for the server analytics that owners on the signature plan will read as insights:
/// every event is a small record that can be sent to the API as it is, once there is an endpoint for it.
@MainActor
enum Analytics {
    enum Event: String, Codable, Sendable {
        /// The business's page was shown.
        case open
        /// The person asked for the way there.
        case navigate
        case call
        /// The person opened the business's own ordering, booking or menu page.
        case order
        /// The person tapped the business's paid placement.
        case sponsored
    }

    struct Record: Codable, Sendable {
        let event: Event
        let business: Int
        let at: Date
    }

    private static let countsKey = "darbEventCounts"
    private static let pendingKey = "darbEventsPending"
    /// The most records kept while waiting for a server to send them to.
    private static let limit = 500

    static func log(_ event: Event, _ business: Int, at date: Date = .now, in defaults: UserDefaults = .standard) {
        // a screen opened by a testing argument is not something a person did
        if defaults === UserDefaults.standard, defaults.string(forKey: "darbRoute") != nil { return }
        var counts = (defaults.dictionary(forKey: countsKey) as? [String: Int]) ?? [:]
        counts[key(event, business), default: 0] += 1
        defaults.set(counts, forKey: countsKey)
        var waiting = pending(in: defaults)
        waiting.append(Record(event: event, business: business, at: date))
        if waiting.count > limit { waiting.removeFirst(waiting.count - limit) }
        if let data = try? JSONEncoder().encode(waiting) { defaults.set(data, forKey: pendingKey) }
    }

    /// How many times this happened to this business on this device.
    static func count(_ event: Event, _ business: Int, in defaults: UserDefaults = .standard) -> Int {
        ((defaults.dictionary(forKey: countsKey) as? [String: Int]) ?? [:])[key(event, business)] ?? 0
    }

    /// The records not yet sent anywhere, oldest first.
    static func pending(in defaults: UserDefaults = .standard) -> [Record] {
        defaults.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
    }

    private static func key(_ event: Event, _ business: Int) -> String { "\(event.rawValue):\(business)" }
}
