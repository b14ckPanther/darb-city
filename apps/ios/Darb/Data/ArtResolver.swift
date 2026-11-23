import Foundation

/// What to draw for a business: a 3D render when a fitting one is in the bundle,
/// otherwise a plain symbol on its sector's colour. A wrong object is never shown as a stand-in.
struct ArtRef: Hashable, Sendable {
    /// The render's name in the bundle; nil means draw the symbol.
    let render: String?
    /// The SF Symbol for the kind, drawn when there is no render.
    let symbol: String
    /// The colour behind the art, as a hex string: the need's colour, or the sector's.
    let tint: String
    /// The business's own logo, as an image name in the bundle. When there is one it is shown instead of the art.
    var logo: String? = nil
    /// The first letter of the business's name, for a placeholder logo.
    var initial: String = ""
}

/// Picks the picture for a business from what is really known about it:
/// its cuisine, then its name, then its kind, then its need, then a symbol.
enum ArtResolver {
    /// Cuisine words as the source writes them in a restaurant's tag, and the dish that stands for each.
    private static let cuisines: [(String, String)] = [
        ("פיצה", "p-pizza"), ("המבורגר", "p-burger"), ("סושי", "p-sushi"), ("יפני", "p-sushi"), ("אסייתי", "p-sushi"),
        ("דגים", "p-fish"), ("עוף", "p-chicken"), ("נקניקיות", "p-sandwich"), ("כריכים", "p-sandwich"),
        ("ארוחות בוקר", "p-breakfast"), ("צ'יפס", "p-fries"), ("איטלקי", "p-pizza"),
        ("שווארמה", "p-shawarma"), ("פלאפל", "p-falafel"), ("חומוס", "p-hummus"), ("גריל", "p-grill"), ("גלידה", "p-icecream"),
    ]
    /// Words in a name that say what the place serves.
    private static let names: [(String, String)] = [
        ("פיצה", "p-pizza"), ("pizza", "p-pizza"), ("בורגר", "p-burger"), ("burger", "p-burger"), ("מקדונלד", "p-burger"),
        ("שווארמה", "p-shawarma"), ("שוארמה", "p-shawarma"), ("פלאפל", "p-falafel"), ("חומוס", "p-hummus"),
        ("גריל", "p-grill"), ("שיפוד", "p-grill"), ("על האש", "p-grill"), ("mashwy", "p-grill"),
        ("סושי", "p-sushi"), ("sushi", "p-sushi"), ("דגים", "p-fish"), ("צ'יקן", "p-chicken"), ("עוף", "p-chicken"),
        ("כריך", "p-sandwich"), ("סנדוויץ", "p-sandwich"), ("בגט", "p-sandwich"), ("טוסט", "p-sandwich"),
        ("גלידה", "p-icecream"), ("גלידריה", "p-icecream"), ("צ'יפס", "p-fries"),
    ]
    /// Kinds whose food is described by cuisine and name.
    private static let foodKinds: Set<String> = ["restaurants", "grill", "hummus", "ice-cream", "sweets", "cafes", "juice-shops"]

    /// A kind's own render. Houses of prayer of every faith share the neutral community building.
    private static let kindRender: [String: String] = [
        "grill": "p-grill", "hummus": "p-hummus", "ice-cream": "p-icecream",
        "schools": "p-school", "kindergartens": "p-kindergarten", "daycare": "p-daycare", "hotels": "p-hotel",
        "fashion": "p-fashion", "kids-clothing": "p-fashion", "public-clinics": "p-clinic", "community-centres": "p-community",
        "sports-clubs": "p-sports", "gyms": "p-gym", "padel": "p-padel", "electronics": "p-electronics",
        "ev-charging": "p-evcharge", "parking": "p-parking", "buses": "p-bus", "aquatic-centres": "p-pool",
        "venues": "p-venue", "kids-venues": "p-venue", "post-offices": "p-post",
        "hairdressers": "p-hair", "barbershops": "p-hair", "salons": "p-hair",
        "synagogues": "p-community", "mosques": "p-community", "churches": "p-community", "druze-prayer-houses": "p-community",
        "senior-centres": "p-community", "youth-clubs": "p-community",
    ]

    /// A plain symbol for a kind. Houses of prayer get a neutral building, never a religious sign.
    private static let kindSymbol: [String: String] = [
        "restaurants": "fork.knife", "cafes": "cup.and.saucer.fill", "grill": "flame.fill", "bakeries": "birthday.cake.fill",
        "hummus": "fork.knife", "sweets": "birthday.cake.fill", "roastery": "leaf.fill", "ice-cream": "birthday.cake.fill",
        "juice-shops": "takeoutbag.and.cup.and.straw.fill", "barbershops": "scissors", "salons": "scissors", "hairdressers": "scissors",
        "nails": "paintbrush.pointed.fill", "cosmetics": "drop.fill", "dental": "cross.case.fill", "physio": "figure.walk", "optics": "eyeglasses",
        "vets": "pawprint.fill", "pharmacies": "pills.fill", "gyms": "dumbbell.fill", "sports-clubs": "sportscourt.fill",
        "padel": "tennis.racket", "aquatic-centres": "figure.pool.swim", "sportswear": "tshirt.fill", "bikes": "bicycle",
        "daycare": "figure.and.child.holdinghands", "kindergartens": "figure.2.and.child.holdinghands", "pediatric": "stethoscope",
        "kids-clothing": "tshirt.fill", "toys": "gift.fill", "kids-venues": "figure.and.child.holdinghands", "art-schools": "music.note",
        "schools": "graduationcap.fill", "vocational": "graduationcap.fill", "software-studios": "chevron.left.forwardslash.chevron.right",
        "it-support": "desktopcomputer", "stations": "fuelpump.fill", "real-estate": "house.fill", "device-repair": "wrench.adjustable.fill",
        "banks": "building.columns.fill", "furniture": "sofa.fill", "factories": "shippingbox.fill", "garages": "wrench.and.screwdriver.fill",
        "car-wash": "car.fill", "ev-charging": "bolt.car.fill", "vehicle-testing": "checkmark.seal.fill", "farm-shops": "carrot.fill",
        "venues": "calendar", "hotels": "bed.double.fill", "camping": "tent.fill", "currency-exchange": "banknote.fill",
        "shops": "cart.fill", "fashion": "tshirt.fill", "bookshops": "book.fill", "plant-shops": "leaf.fill", "pet-shops": "pawprint.fill",
        "gold": "diamond.fill", "electronics": "iphone", "kitchenware": "fork.knife",
        "mosques": "building.columns.fill", "churches": "building.columns.fill", "synagogues": "building.columns.fill",
        "druze-prayer-houses": "building.columns.fill", "islamic-books": "book.closed.fill", "janazah": "building.columns.fill",
        "municipal": "building.2.fill", "public-clinics": "cross.case.fill", "libraries": "books.vertical.fill",
        "post-offices": "envelope.fill", "buses": "bus.fill", "parking": "parkingsign", "water": "drop.fill",
        "emergency": "staroflife.fill", "nonprofits": "heart.fill", "community-centres": "person.3.fill",
        "senior-centres": "figure.2", "youth-clubs": "person.2.fill",
    ]

    /// The plain symbol of a kind, when it has one of its own.
    static func symbol(kind: String) -> String? { kindSymbol[kind] }

    /// - Parameters:
    ///   - need: the everyday need the kind belongs to, when it has one.
    ///   - sector: the kind's sector, for the symbol's colour.
    ///   - exists: whether a render of that name is in the bundle. A render that has not landed yet is skipped.
    static func resolve(_ b: Business, need: Need?, sector: Sector?, exists: (String) -> Bool) -> ArtRef {
        let symbol = kindSymbol[b.kind] ?? sector?.symbol ?? "mappin"
        let tint = need.map { String(format: "%06X", $0.hex) } ?? sector?.accent ?? "8F9BC4"
        func found(_ name: String?) -> ArtRef? {
            guard let name, exists(name) else { return nil }
            return ArtRef(render: name, symbol: symbol, tint: tint)
        }
        if foodKinds.contains(b.kind) {
            // 1. the cuisine the source gives
            // the cuisine words are matched in Hebrew, whatever language the app is in
            let tag = b.tags?.he ?? ""
            for (word, render) in cuisines where tag.contains(word) { if let r = found(render) { return r } }
            // 2. what the name says
            let name = (b.names.he + " " + b.names.en).lowercased()
            for (word, render) in names where name.contains(word) { if let r = found(render) { return r } }
        }
        // 3. the kind's own object, 4. the need's object, 5. a symbol on the sector's colour
        return found(kindRender[b.kind]) ?? found(need?.art) ?? ArtRef(render: nil, symbol: symbol, tint: tint)
    }
}
