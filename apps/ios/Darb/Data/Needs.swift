import SwiftUI

/// What the place page shows for a kind of business.
enum PageKind: Sendable, Hashable {
    /// Dishes or products with prices.
    case menu
    /// A fuel price board.
    case fuelBoard
    /// Services with their progress.
    case services
    /// The bank branch.
    case branch
}

/// The everyday needs on the home screen, each with its 3D object and colour.
struct Need: Sendable, Hashable, Identifiable {
    let key: String
    let he: String
    let kinds: [String]
    let art: String
    let hex: UInt32
    let page: PageKind
    let pageTitle: String
    /// Which sample screen to show when a kind has none of its own.
    let screen: String
    var id: String { key }
    var color: Color { Color(hex: hex) }
    /// The need's name in the language in use.
    var title: String { L(he) }
    /// The name on a home tile, where every name has to fit one line.
    var short: String { key == "pharmacy" ? L("מרקחת") : L(he) }
    /// The title of the page a paying business fills: its menu, its prices, its services.
    var pageName: String { L(pageTitle) }

    static let all: [Need] = [
        Need(key: "food", he: "אוכל", kinds: ["restaurants", "grill", "hummus"], art: "p-plate", hex: 0xFF5533, page: .menu, pageTitle: "תפריט", screen: "restaurants"),
        Need(key: "sweets", he: "מתוקים", kinds: ["sweets", "ice-cream"], art: "p-kunafa", hex: 0xFF7FBE, page: .menu, pageTitle: "מגשים", screen: "sweets"),
        Need(key: "coffee", he: "קפה", kinds: ["cafes"], art: "p-coffee", hex: 0xFF9A2E, page: .menu, pageTitle: "תפריט", screen: "cafes"),
        Need(key: "bakery", he: "מאפייה", kinds: ["bakeries"], art: "p-bread", hex: 0xFFC330, page: .menu, pageTitle: "מה חם", screen: "bakeries"),
        Need(key: "pharmacy", he: "בית מרקחת", kinds: ["pharmacies"], art: "p-pills", hex: 0x3DDC97, page: .menu, pageTitle: "המדף", screen: "pharmacies"),
        Need(key: "grocery", he: "מכולת", kinds: ["shops"], art: "p-crate", hex: 0xC8F03C, page: .menu, pageTitle: "המדף", screen: "shops"),
        Need(key: "fuel", he: "דלק", kinds: ["stations"], art: "p-pump", hex: 0x66CCFF, page: .fuelBoard, pageTitle: "מחירים", screen: "stations"),
        Need(key: "garage", he: "מוסך", kinds: ["garages"], art: "p-garage", hex: 0xB79CFF, page: .services, pageTitle: "שירותים", screen: "garages"),
        Need(key: "bank", he: "בנק", kinds: ["banks"], art: "p-coins", hex: 0xF2EBE0, page: .branch, pageTitle: "הסניף", screen: "banks"),
    ]
    static func byKey(_ k: String) -> Need? { all.first { $0.key == k } }
    static func forKind(_ slug: String) -> Need? { all.first { $0.kinds.contains(slug) } }

    /// The part of the day an hour falls in, for remembering what the person opens when.
    static func part(hour h: Int) -> String {
        switch h {
        case ..<6: "night"
        case ..<11: "morning"
        case ..<16: "midday"
        case ..<21: "evening"
        default: "late"
        }
    }

    /// Which needs lead at this hour of the day.
    static func order(hour h: Int) -> [String] {
        switch h {
        case ..<6: return ["pharmacy", "fuel", "food", "grocery", "sweets", "coffee", "bakery", "garage", "bank"]
        case ..<11: return ["bakery", "coffee", "pharmacy", "fuel", "grocery", "garage", "bank", "food", "sweets"]
        case ..<16: return ["food", "coffee", "bank", "pharmacy", "fuel", "garage", "grocery", "sweets", "bakery"]
        case ..<21: return ["food", "sweets", "coffee", "fuel", "pharmacy", "grocery", "bakery", "garage", "bank"]
        default: return ["pharmacy", "food", "fuel", "sweets", "grocery", "coffee", "bakery", "garage", "bank"]
        }
    }
}

/// Where the app can go: a need, any kind, or one business.
enum Route: Hashable, Sendable {
    case need(String)
    case kind(String)
    case business(Int)

    var isNeed: Bool { if case .need = self { true } else { false } }
}

extension Sector {
    /// A plain symbol for each sector, for kinds that have no 3D object of their own.
    var symbol: String {
        switch slug {
        case "food": "fork.knife"
        case "beauty": "scissors"
        case "health": "cross.case.fill"
        case "sports": "figure.run"
        case "kids": "figure.and.child.holdinghands"
        case "education": "graduationcap.fill"
        case "tech": "laptopcomputer"
        case "services": "wrench.and.screwdriver.fill"
        case "home": "sofa.fill"
        case "industry": "shippingbox.fill"
        case "auto": "car.fill"
        case "agriculture": "leaf.fill"
        case "events": "calendar"
        case "travel": "suitcase.fill"
        case "retail": "bag.fill"
        case "faith": "building.columns.fill"
        case "civic": "building.2.fill"
        case "community": "person.3.fill"
        default: "mappin"
        }
    }
    /// The sector's name in the language in use. One is renamed in the app, to keep to the copy rules.
    var title: String { slug == "faith" ? L("מבני ציבור וקהילה") : name.now }
    /// The sector in the same warm family as the home tiles.
    var color: Color { Sector.family[slug].map { Color(hex: $0) } ?? Color(hexString: accent) }
    static let family: [String: UInt32] = [
        "food": 0xF26A3D, "beauty": 0xE89A8A, "health": 0x7CC48C, "sports": 0xF7A440, "kids": 0xFFC330,
        "education": 0x8EC3B0, "tech": 0xBACD52, "services": 0xD8C9A8, "home": 0xD9A066, "industry": 0xD8C9A8,
        "auto": 0x8EC3B0, "agriculture": 0xBACD52, "events": 0xFFC330, "travel": 0xF7A440, "retail": 0xE89A8A,
        "faith": 0x7CC48C, "civic": 0xD8C9A8, "community": 0xF26A3D,
    ]
}
