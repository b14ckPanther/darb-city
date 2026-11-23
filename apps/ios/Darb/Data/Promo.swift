import Foundation

// How Darb earns, in one rule: the honest answer is never for sale.
// The need tiles and the lead card always show the truly nearest open place. Payment buys a labelled placement
// next to that answer, a richer page, and visibility (a logo, a cover). It never buys rank, and it never breaks a tie.

/// What Darb sells to businesses, and who has bought it. Written from packages/seed/data by scripts/export-data.py.
struct Promo: Decodable, Sendable {
    let plans: [Plan]
    /// The pricing page's own copy, by key ("pricing.title"), as the website carries it.
    let texts: [String: Tri]
    let sponsorships: [Sponsorship]
    let profiles: [BusinessProfile]

    static let empty = Promo(plans: [], texts: [:], sponsorships: [], profiles: [])

    func text(_ key: String) -> String { texts[key]?.now ?? "" }
}

/// One of Darb's plans for a business, with its features, price and notes in the three languages.
///   presence   free: the listing itself, with its name, hours, navigation and a call button.
///   spotlight  ₪89 a month: a professional page (logo, cover, photos, menu or prices, WhatsApp) and labelled placements.
///   signature  ₪349 a month: a site of its own, and insights on what people did with the listing (see `Analytics`).
///   ecosystem  an app and a full system built by Darb: ordering or booking straight from the page.
struct Plan: Decodable, Sendable, Identifiable {
    let slug: String
    let name: Tri
    let tagline: Tri
    /// Shekels a month; nil when the price is set after a call.
    let monthly: Int?
    /// A one-time setup price in shekels, when there is one.
    let setup: Int?
    let priceNote: Tri?
    let features: [String: [String]]
    let highlighted: Bool
    let cta: Tri?
    var id: String { slug }
    var isPaid: Bool { monthly != 0 }
    var title: String { name.now }
    /// The plan's features in the language in use.
    var points: [String] { features[Lang.current.rawValue] ?? features["he"] ?? [] }
}

/// A paid placement: always labelled as paid, always beside the honest answer and never instead of it.
/// None are sold yet, so the bundled list is empty and each slot shows Darb's own card; a sponsor is never made up.
struct Sponsorship: Decodable, Sendable {
    enum Slot: String, Decodable, Sendable {
        /// The sponsored card on the home screen, taking turns with the other sponsors in the area.
        case home
        /// The first card on the page of the business's own need or kind, when it is nearly as near as the nearest.
        case page
    }
    /// The listing the placement is for.
    let business: Int
    /// The plan that pays for it.
    let plan: String
    let slots: [Slot]
    /// The towns it runs in, as place slugs; nil means anywhere within driving distance.
    let area: [String]?
    /// Made by the `-darbDemoSponsor` testing argument, and marked as a demo wherever it shows.
    var demo = false

    private enum CodingKeys: String, CodingKey { case business, plan, slots, area }

    /// A page placement only shows a sponsor at most this many minutes further than the nearest place.
    static let pageDetour = 5
}

/// What a business shows beyond its bare listing.
///
/// Free for every business, shown whenever the data has it: a logo, a cover, up to three photos, a picture of the
/// storefront (how the place looks from the street, to find it on arrival), and WhatsApp.
/// Paid: a live menu or prices and unlimited photos (spotlight and signature); ordering, booking and a
/// Darb-built app (ecosystem).
///
/// No business in the data has given a picture yet. Every surface is designed to look finished without one,
/// and a slot is never filled with a made-up or scraped photo. Names starting "demo:" are not pictures:
/// they are drawn placeholders, used only by the `-darbDemoMedia` testing argument and always marked as a demo.
struct BusinessProfile: Decodable, Sendable {
    struct Item: Decodable, Sendable, Hashable { let label: Tri; let meta: Tri? }
    struct Palette: Decodable, Sendable { let bg: String; let surface: String; let ink: String; let accent: String }

    /// The listing's id in the data.
    let id: Int
    /// The plan the business is on.
    let plan: String

    // free for every business
    var logo: String?
    var cover: String?
    var photos: [String]
    /// How the place looks from the street.
    var storefront: String?
    let whatsapp: String?
    let taglines: Tri?
    let addresses: Tri?
    let phone: String?
    /// The business's own colours, when Darb built its app or site.
    let palette: Palette?

    // paid
    let menuURL: URL?
    let orderURL: URL?
    let bookingURL: URL?
    /// What the business itself published: menu sections, prices, services.
    let items: [Item]
    let tagList: [Tri]
    /// A screen of the business's own Darb-built app, as an image name in the bundle.
    let app: String?

    /// Made by a testing argument (`-darbDemoMedia`, `-darbDemoProfile`), and marked as a demo wherever it shows.
    var demo = false

    private enum CodingKeys: String, CodingKey {
        case id, plan, logo, cover, photos, storefront, whatsapp, phone, palette, menuURL, orderURL, bookingURL, items, app
        case taglines = "tagline", addresses = "address", tagList = "tags"
    }

    var tagline: String? { taglines?.now }
    var address: String? { addresses?.now }
    var tags: [String] { tagList.map(\.now) }

    /// A free listing shows this many photos; a paid one shows them all.
    static let freePhotos = 3

    enum Action: Sendable { case order, booking, menu }
    /// Ordering, booking or a menu: the one thing to do from the page besides going there.
    var action: (title: String, url: URL, kind: Action)? {
        if let u = orderURL { return (L("הזמנה"), u, .order) }
        if let u = bookingURL { return (L("קביעת תור"), u, .booking) }
        if let u = menuURL { return (L("תפריט"), u, .menu) }
        return nil
    }

    var hasMedia: Bool { logo != nil || cover != nil || !photos.isEmpty || storefront != nil }

    /// A stand-in for the testing arguments: a listing with no profile of its own, on a plan.
    static func stand(for business: Int, plan: String) -> BusinessProfile {
        var p = BusinessProfile(id: business, plan: plan, logo: nil, cover: nil, photos: [], storefront: nil, whatsapp: nil, taglines: nil, addresses: nil,
                                phone: nil, palette: nil, menuURL: nil, orderURL: nil, bookingURL: nil, items: [], tagList: [], app: nil)
        p.demo = true
        return p
    }

    /// The same profile with drawn placeholders in every empty picture slot, for `-darbDemoMedia`.
    func withPlaceholders() -> BusinessProfile {
        var p = self
        p.logo = p.logo ?? "demo:logo"
        p.cover = p.cover ?? "demo:cover"
        if p.photos.isEmpty { p.photos = ["demo:photo1", "demo:photo2", "demo:photo3"] }
        p.storefront = p.storefront ?? "demo:storefront"
        return p
    }
}
