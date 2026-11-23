import Foundation
import Security

/// Darb loyalty, as the server sends it (packages/contracts/src/loyalty.ts).
struct LoyaltyOffer: Codable, Sendable, Identifiable, Hashable {
    struct Business: Codable, Sendable, Hashable { let id: String; let slug: String; let placeSlug: String; let name: [String: String] }
    let id: String
    let business: Business
    let title: [String: String]
    let reward: [String: String]
    let goal: Int
    let cooldownMinutes: Int
    let active: Bool
}

struct LoyaltyStanding: Codable, Sendable, Identifiable, Hashable {
    let offer: LoyaltyOffer
    let stamps: Int
    let ready: Bool
    let lastStampAt: String?
    let nextStampAt: String?
    let rewards: Int
    var id: String { offer.id }
}

struct LoyaltyCard: Codable, Sendable { let code: String; let standings: [LoyaltyStanding] }

/// A text in the language in use, else Hebrew, else any.
func pick(_ t: [String: String]) -> String {
    t[Lang.current.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? t["he"] ?? t.values.first ?? ""
}

enum LoyaltyAPI {
    enum Failure: Error, Equatable {
        case notACard, notStaff, tooSoon(next: Date?), rewardReady, notReady, gone, offline, unavailable
    }

    private static let decoder = JSONDecoder()

    // MARK: the visitor's own card

    /// The card's secret on this phone: the card is made the first time it is needed, and its secret kept.
    private static func secret() async throws -> String {
        if let kept = CardKeychain.secret { return kept }
        var req = URLRequest(url: DarbAPI.base.appendingPathComponent("loyalty/cards"), timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = Data("{}".utf8)
        let (data, res) = try await URLSession.shared.data(for: req)
        guard (res as? HTTPURLResponse)?.statusCode == 201,
              let made = try? decoder.decode([String: String].self, from: data), let s = made["secret"] else { throw Failure.offline }
        CardKeychain.secret = s
        return s
    }

    /// The card as an Apple Wallet pass, signed by Darb's server.
    static func walletPass() async throws -> Data {
        for attempt in 0..<2 {
            var req = URLRequest(url: DarbAPI.base.appendingPathComponent("loyalty/cards/me/pass"), timeoutInterval: 30)
            req.setValue(try await secret(), forHTTPHeaderField: "x-darb-card")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, res) = try await URLSession.shared.data(for: req)
            switch (res as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: return data
            case 503: throw Failure.unavailable
            // the card is gone from the server: forget it and make a new one, once
            case 404 where attempt == 0: CardKeychain.secret = nil
            default: throw Failure.offline
            }
        }
        throw Failure.offline
    }

    /// What the card's QR holds: the counter's page for this card, which a phone's camera opens directly.
    static func scanURL(_ code: String) -> URL {
        URL(string: "https://darb.co.il/helpers/stamp/\(code)")!
    }

    /// A card code from what a camera read: the counter's link, or the bare code.
    static func code(from scanned: String) -> String? {
        let raw = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = raw.split(separator: "/").last.map(String.init) ?? raw
        let code = tail.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        let alphabet = Set("23456789ABCDEFGHJKMNPQRSTVWXYZ")
        return code.count == 10 && code.allSatisfy(alphabet.contains) ? code : nil
    }

    // MARK: the counter

    static func staffOffers() async throws -> [LoyaltyOffer] {
        let (data, status) = try await DarbAPI.authorized("loyalty/staff/offers")
        guard status == 200 else { return [] }
        return try decoder.decode([LoyaltyOffer].self, from: data)
    }

    static func card(_ code: String) async throws(Failure) -> LoyaltyCard {
        guard let (data, status) = try? await DarbAPI.authorized("loyalty/staff/cards/\(code)") else { throw .offline }
        switch status {
        case 200: guard let card = try? decoder.decode(LoyaltyCard.self, from: data) else { throw .offline }; return card
        case 404: throw .notACard
        case 403: throw .notStaff
        default: throw .offline
        }
    }

    static func stamp(_ code: String, offer: String, redeem: Bool) async throws(Failure) -> LoyaltyStanding {
        let body = try? JSONEncoder().encode(["code": code, "offerId": offer])
        guard let (data, status) = try? await DarbAPI.authorized(redeem ? "loyalty/staff/redeem" : "loyalty/staff/stamp", method: "POST", body: body)
        else { throw .offline }
        switch status {
        case 200: guard let s = try? decoder.decode(LoyaltyStanding.self, from: data) else { throw .offline }; return s
        case 404: throw .notACard
        case 403: throw .notStaff
        case 409:
            let e = try? decoder.decode([String: String].self, from: data)
            switch e?["code"] {
            case "too_soon": throw .tooSoon(next: e?["nextStampAt"].flatMap(Self.date))
            case "reward_ready": throw .rewardReady
            default: throw .notReady
            }
        default: throw .offline
        }
    }

    // MARK: Darb's admin

    struct NewOffer: Encodable {
        var businessId: String
        var title: [String: String]
        var reward: [String: String]
        var goal: Int
        var cooldownMinutes: Int
        var active = true
    }

    static func allOffers() async throws -> [LoyaltyOffer] {
        let (data, status) = try await DarbAPI.authorized("admin/loyalty/offers")
        guard status == 200 else { throw Failure.notStaff }
        return try decoder.decode([LoyaltyOffer].self, from: data)
    }

    static func create(_ offer: NewOffer) async throws -> LoyaltyOffer {
        let (data, status) = try await DarbAPI.authorized("admin/loyalty/offers", method: "POST", body: JSONEncoder().encode(offer))
        guard status == 201 else { throw Failure.offline }
        return try decoder.decode(LoyaltyOffer.self, from: data)
    }

    static func setActive(_ id: String, _ active: Bool) async throws {
        _ = try await DarbAPI.authorized("admin/loyalty/offers/\(id)", method: "PATCH", body: JSONEncoder().encode(["active": active]))
    }

    /// A staff invite link for a business, to share once.
    static func invite(_ businessId: String) async throws -> URL {
        let (data, status) = try await DarbAPI.authorized("admin/loyalty/businesses/\(businessId)/invite", method: "POST", body: Data("{}".utf8))
        guard status == 201, let made = try? decoder.decode([String: String].self, from: data), let token = made["token"],
              let url = URL(string: "https://darb.co.il/helpers/stamp/join/\(token)") else { throw Failure.offline }
        return url
    }

    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

/// The card's secret, in the Keychain: it survives a reinstall, never leaves the phone, and is the only way to read
/// the card.
enum CardKeychain {
    private static var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "il.co.darb.loyalty",
        kSecAttrAccount as String: "card",
    ] }

    static var secret: String? {
        get {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(query as CFDictionary)
            guard let newValue else { return }
            var q = query
            q[kSecValueData as String] = Data(newValue.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
