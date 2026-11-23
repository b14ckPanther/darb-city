import Foundation

/// A Deluxe client whose shop Darb draws itself, natively, from the client's own system. The key here is the
/// client's public, read-only key: the same one their own website ships to every visitor.
struct ShopSource: Sendable {
    /// Which kind of system the client's shop is kept in, as Darb built it for them.
    enum System: Sendable {
        /// A restaurant's menu: categories with photos, dishes with photos, sizes, four languages (Caramel).
        case kitchen
        /// A shop of products standing on their own colours, chosen by hair type, in Arabic (Raghad Beauty).
        case shelf
        /// A car lot: cars by body type, each with its photos and its facts, asked about on WhatsApp (Abu Firas).
        case lot
    }
    /// Whether picks go into a bag and are ordered together; a lot is asked about one car at a time.
    var orders: Bool { system != .lot }
    let system: System
    let base: URL
    let key: String
    /// The client's colours, for their world inside Darb. `light` is a pale world drawn in the light look.
    let bg: UInt32, surface: UInt32, ink: UInt32, accent: UInt32
    var light = false
    /// The languages the business keeps its shop in, the first being its own.
    var langs: [ShopLang] = ShopLang.allCases
    /// The logo, when the client's system keeps none of its own.
    var logo: URL? = nil
    /// Where orders are sent, as WhatsApp digits.
    let whatsapp: String
    /// The business's own website, for the link to an item in a WhatsApp question.
    var site: URL? = nil

    /// The language the shop is read in: the one asked for when the business keeps it, otherwise its own.
    func lang(_ wanted: ShopLang) -> ShopLang { langs.contains(wanted) ? wanted : langs[0] }

    /// The clients whose shop is drawn in Darb, by the business's id in the data.
    static let all: [Int: ShopSource] = [
        // Caramel, Akko: gluten-free restaurant and patisserie
        1419998672: ShopSource(system: .kitchen,
                               base: URL(string: "https://errfhykkpwlslmgarcoe.supabase.co")!, key: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVycmZoeWtrcHdsc2xtZ2FyY29lIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc5ODIxOTQsImV4cCI6MjEwMzU1ODE5NH0.vIf35F1aeRCrUq5_CEDUS04X2BPkZdoU_rTQv5J6o7s",
                               bg: 0x0D0806, surface: 0x1F1712, ink: 0xFBF3E6, accent: 0xE9A43A,
                               whatsapp: "972524382229"),
        // Raghad Beauty, Nahf: Skala hair creams and masks
        729741531: ShopSource(system: .shelf,
                              base: URL(string: "https://bvmtbmpjppangdqjdvpx.supabase.co")!, key: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ2bXRibXBqcHBhbmdkcWpkdnB4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwMTk5OTcsImV4cCI6MjEwNjU5NTk5N30.aR0fsMgjtAu-T3EIcuhVMZmE8zRJ0-E7H4iOIVK_KWw",
                              bg: 0xFDEBF1, surface: 0xFFFFFF, ink: 0x26102B, accent: 0xB4125F, light: true,
                              langs: [.ar], logo: URL(string: "https://raghad.darb.co.il/icons/icon-512.png"),
                              whatsapp: "972504774367"),
        // Rechev Abu Firas, Nahf: used cars
        596130324: ShopSource(system: .lot,
                              base: URL(string: "https://zgayfxymgwspukmrqfxp.supabase.co")!, key: "sb_publishable_j_oqzELG3k05gOkjyRczRQ_ZVnK17uW",
                              bg: 0x14161A, surface: 0x1F2227, ink: 0xECE8DF, accent: 0xF2A33A,
                              langs: [.ar, .he], logo: URL(string: "https://naiefcar.darb.co.il/icons/icon-512.png"),
                              whatsapp: "972547227619", site: URL(string: "https://naiefcar.darb.co.il")),
    ]
}
