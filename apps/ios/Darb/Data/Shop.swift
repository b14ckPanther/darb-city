import Foundation

/// A Deluxe client's shop as Darb shows it: its look, its photos, and its menu or shelf by category, in one language.
struct Shop: Codable, Sendable {
    struct Category: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let name: String
        let subtitle: String?
        let image: URL?
        /// A hair type's curl, from straight (0) to coily (1): drawn as a strand instead of a photo.
        var curl: Double? = nil
    }
    struct Item: Codable, Sendable, Identifiable, Hashable {
        let id: String
        /// Every category the item shows under.
        let categories: [String]
        let name: String
        /// The name as printed on the product, when it differs from the one in the shop's language.
        var line: String? = nil
        let note: String?
        /// Nil when the business has not priced it yet: it is shown, and cannot be ordered.
        let price: Double?
        /// Small, medium and large prices, when the dish comes in sizes.
        let sizes: [Double]?
        let image: URL?
        let available: Bool
        let badge: String?
        /// The colour the product stands on: set for products photographed cut out, like jars.
        var tint: UInt32? = nil
        /// What it is for, in a few words each: hair types, needs.
        var tags: [String]? = nil
        /// The amount in the pack, as printed; for a car, its number on the lot.
        var detail: String? = nil
        /// Every photo, when there is more than one (a car's).
        var gallery: [URL]? = nil
        /// The question sent on WhatsApp about this one item, in the business's own words.
        var ask: String? = nil
    }
    let name: String
    let tagline: String?
    let logo: URL?
    let heroes: [URL]
    let categories: [Category]
    let items: [Item]
    /// The products the business puts in front, shown in the window when it keeps no photos of its own.
    var featured: [String] = []
    /// The smallest order the business takes.
    var minOrder: Double? = nil
    /// How the business delivers and is paid, in its own words.
    var note: String? = nil
    /// When this copy was read from the business's own system.
    let fetched: Date

    var windowItems: [Item] { featured.compactMap { id in items.first { $0.id == id } } }
}

/// The languages a shop can be read in: Darb's three, and any more the business keeps, like Russian at Caramel.
enum ShopLang: String, CaseIterable, Identifiable, Sendable {
    case he, ar, en, ru
    var id: String { rawValue }
    var endonym: String { switch self { case .he: "עברית"; case .ar: "العربية"; case .en: "English"; case .ru: "Русский" } }
    var isRTL: Bool { self == .he || self == .ar }
    var locale: Locale { Locale(identifier: rawValue) }
    /// Darb's own words around the shop follow it; Russian, which Darb does not speak, gets English.
    var ui: Lang { Lang(rawValue: rawValue) ?? .en }
    init(_ l: Lang) { self = ShopLang(rawValue: l.rawValue) ?? .he }
}

/// Reads a client's shop from their own system and keeps the last copy on the phone, so it opens at once and
/// works without signal. A fresh copy is read every time the shop opens.
enum ShopLoader {
    /// Saves a shop's pictures to the phone ahead of time, a few at a time, at low priority. With `ready`, the ones
    /// seen first (the window, the logo, the categories and the first of each) are also decoded into memory, so the
    /// shop opens with them already drawn.
    static func warm(_ shop: Shop?, ready: Bool = false) async {
        guard let shop else { return }
        var first = shop.heroes + [shop.logo].compactMap { $0 } + shop.categories.compactMap(\.image) + shop.windowItems.compactMap(\.image)
        for c in shop.categories { first += shop.items.filter { $0.categories.contains(c.id) }.prefix(6).compactMap(\.image) }
        var seen = Set<URL>()
        first = first.filter { seen.insert($0).inserted }
        let rest = shop.items.compactMap(\.image).filter { seen.insert($0).inserted }
        await withTaskGroup(of: Void.self) { g in
            for (i, url) in first.enumerated() {
                if i >= 6 { await g.next() }
                g.addTask(priority: .utility) { if ready { _ = await ImageStore.shared.image(url) } else { await ImageStore.shared.keep(url) } }
            }
        }
        await withTaskGroup(of: Void.self) { g in
            for (i, url) in rest.enumerated() {
                if i >= 4 { await g.next() }
                g.addTask(priority: .background) { await ImageStore.shared.keep(url) }
            }
        }
    }

    static func cached(_ id: Int, lang: ShopLang) -> Shop? {
        guard let s = ShopSource.all[id], let data = try? Data(contentsOf: file(id, s.lang(lang))) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Shop.self, from: data)
    }

    static func fetch(_ id: Int, lang wanted: ShopLang) async throws -> Shop {
        guard let s = ShopSource.all[id] else { throw URLError(.badURL) }
        let lang = s.lang(wanted)
        let shop = switch s.system {
        case .kitchen: try await kitchen(s, lang)
        case .shelf: try await shelf(s, lang)
        case .lot: try await lot(s, lang)
        }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? enc.encode(shop).write(to: file(id, lang))
        return shop
    }

    // MARK: a restaurant's menu (Caramel)

    private struct KitchenRow: Decodable {
        let id: Int
        let category_id: Int?
        let name: String?
        let name_ar: String?, name_en: String?, name_ru: String?
        let subtitle: String?, subtitle_ar: String?, subtitle_en: String?, subtitle_ru: String?
        let short_description: String?, short_description_ar: String?, short_description_en: String?, short_description_ru: String?
        let price: Double?, price_s: Double?, price_m: Double?, price_l: Double?
        let storage_path: String?
        let is_available: Bool?
        let badge: String?
        let logo_storage_path: String?
    }

    private static func kitchen(_ s: ShopSource, _ lang: ShopLang) async throws -> Shop {
        async let cats: [KitchenRow] = rows(s, "categories?select=*&is_visible=eq.true&order=sort_order")
        async let items: [KitchenRow] = rows(s, "menu_items?select=*&is_visible=eq.true&order=sort_order")
        async let profile: [KitchenRow] = rows(s, "restaurant_profile?select=*&limit=1")
        async let heroes: [KitchenRow] = rows(s, "hero_media?select=*&is_visible=eq.true&type=eq.image&order=sort_order")
        let (c, i, p, h) = try await (cats, items, profile, heroes)
        func pick(_ he: String?, _ ar: String?, _ en: String?, _ ru: String? = nil) -> String? {
            let v: String? = switch lang { case .he: he; case .ar: ar ?? he; case .en: en ?? he; case .ru: ru ?? en ?? he }
            return v.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        }
        func media(_ bucket: String, _ path: String?) -> URL? {
            path.map { s.base.appendingPathComponent("storage/v1/object/public/\(bucket)/\($0)") }
        }
        let prof = p.first
        return Shop(
            name: pick(prof?.name, prof?.name_ar, prof?.name_en, prof?.name_ru) ?? "",
            tagline: pick(prof?.subtitle, prof?.subtitle_ar, prof?.subtitle_en, prof?.subtitle_ru),
            logo: media("branding", prof?.logo_storage_path) ?? s.logo,
            heroes: h.compactMap { media("hero", $0.storage_path) },
            categories: c.map { Shop.Category(id: String($0.id), name: pick($0.name, $0.name_ar, $0.name_en, $0.name_ru) ?? "", subtitle: pick($0.subtitle, $0.subtitle_ar, $0.subtitle_en, $0.subtitle_ru), image: media("categories", $0.storage_path)) },
            items: i.compactMap { r in
                guard let cat = r.category_id else { return nil }
                let sizes = [r.price_s, r.price_m, r.price_l].compactMap { $0 }
                return Shop.Item(id: String(r.id), categories: [String(cat)], name: pick(r.name, r.name_ar, r.name_en, r.name_ru) ?? "",
                                 note: pick(r.short_description, r.short_description_ar, r.short_description_en, r.short_description_ru),
                                 price: r.price ?? 0, sizes: sizes.count == 3 ? sizes : nil,
                                 image: media("menu-items", r.storage_path), available: r.is_available ?? true, badge: r.badge)
            },
            fetched: .now)
    }

    // MARK: a shelf of products (Raghad Beauty)

    private struct Product: Decodable {
        let id: String
        let brand: String?
        let name: String?, name_ar: String?
        let summary: String?
        let need: [String]?, hair: [String]?
        let size: String?
        let price: Double?
        let img: String?
        let bg: String?
        let available: Bool?
        let featured: Bool?
    }
    private struct Named: Decodable { let id: String; let name: String; let curl: Double? }
    private struct Content<V: Decodable>: Decodable { let value: V }
    private struct Settings: Decodable {
        let storeName: String?, storeNameAr: String?, tagline: String?
        let minOrder: Double?
        let orderNote: String?, deliveryNote: String?
    }
    private struct Hero: Decodable { let title: String? }

    private static func shelf(_ s: ShopSource, _ lang: ShopLang) async throws -> Shop {
        async let products: [Product] = rows(s, "products?select=*&visible=eq.true&order=sort_order")
        async let hairs: [Named] = rows(s, "hair_types?select=id,name,curl&order=sort_order")
        async let needs: [Named] = rows(s, "needs?select=id,name&order=sort_order")
        async let brands: [Named] = rows(s, "brands?select=id,name&order=sort_order")
        async let settings: [Content<Settings>] = rows(s, "site_content?select=value&key=eq.settings")
        async let hero: [Content<Hero>] = rows(s, "site_content?select=value&key=eq.hero")
        let (p, h, n, b, set, her) = try await (products, hairs, needs, brands, settings, hero)
        let st = set.first?.value
        let hairName = Dictionary(h.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let needName = Dictionary(n.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let brandName = Dictionary(b.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        func clean(_ v: String?) -> String? { v.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
        let all = Shop.Category(id: "*", name: L("הכל", in: lang.ui), subtitle: nil, image: nil)
        let items = p.map { r in
            let latin = [r.brand.flatMap { brandName[$0] }, clean(r.name)].compactMap { $0 }.joined(separator: " ")
            return Shop.Item(
                id: r.id, categories: ["*"] + (r.hair ?? []),
                name: clean(r.name_ar) ?? clean(r.name) ?? "", line: latin.isEmpty ? nil : latin,
                note: clean(r.summary), price: r.price, sizes: nil,
                image: r.img.flatMap { URL(string: $0) }, available: r.available ?? true, badge: nil,
                tint: r.bg.flatMap { UInt32($0.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) },
                tags: (r.need ?? []).compactMap { needName[$0] } + (r.hair ?? []).compactMap { hairName[$0] },
                detail: clean(r.size))
        }
        return Shop(
            name: (lang == .ar ? clean(st?.storeNameAr) : nil) ?? clean(st?.storeName) ?? "",
            tagline: clean(her.first?.value.title) ?? clean(st?.tagline),
            logo: s.logo, heroes: [],
            categories: [all] + h.map { Shop.Category(id: $0.id, name: $0.name, subtitle: nil, image: nil, curl: $0.curl) },
            items: items,
            featured: p.filter { $0.featured == true }.map(\.id),
            minOrder: st?.minOrder,
            note: [clean(st?.deliveryNote), clean(st?.orderNote)].compactMap { $0 }.joined(separator: " "),
            fetched: .now)
    }

    // MARK: a car lot (Rechev Abu Firas)

    private struct Car: Decodable {
        let id: String
        let stock_no: Int
        let make: String, model: String
        let trim: String?
        let year: Int
        let km: Int?, hand: Int?, price: Int?, prev_price: Int?
        let gearbox: String?, fuel: String?, body: String?
        let color_ar: String?, color_he: String?
        let status: String
        let sold_at: String?
        let photos: [String]?
        let notes_ar: String?, notes_he: String?
        let featured: Bool?
        let position: Int?
        let created_at: String?
    }
    private struct Lot: Decodable {
        let name_ar: String?, name_he: String?
        let tagline_ar: String?, tagline_he: String?
        let sold_visible_days: Int?
        let payment_ar: [String]?, payment_he: [String]?
    }

    /// Car makes and models written in Hebrew, by their brand names.
    private static let brandNames: [String: String] = [
        "סקודה": "Skoda", "פולקסווגן": "Volkswagen", "פוקסווגן": "Volkswagen", "סיאט": "Seat", "רנו": "Renault",
        "טויוטה": "Toyota", "מאזדה": "Mazda", "סוזוקי": "Suzuki", "סיטרואן": "Citroën", "אופל": "Opel", "יונדאי": "Hyundai",
        "קיה": "Kia", "ניסאן": "Nissan", "הונדה": "Honda", "מיצובישי": "Mitsubishi", "פיג'ו": "Peugeot", "פיגו": "Peugeot",
        "שברולט": "Chevrolet", "פורד": "Ford", "ב.מ.וו": "BMW", "במוו": "BMW", "מרצדס": "Mercedes", "אאודי": "Audi",
        "פיאט": "Fiat", "סובארו": "Subaru", "דאצ'יה": "Dacia", "לקסוס": "Lexus", "ג'יפ": "Jeep", "וולוו": "Volvo",
        "אוקטביה": "Octavia", "אוקטאביה": "Octavia", "סופרב": "Superb", "פאביה": "Fabia", "קודיאק": "Kodiaq", "קארוק": "Karoq",
        "איביזה": "Ibiza", "לאון": "Leon", "גולף": "Golf", "פולו": "Polo", "פאסאט": "Passat", "שירוקו": "Scirocco", "טיגואן": "Tiguan",
        "גרנד": "Grand", "קופה": "Coupe", "מגאן": "Megane", "קליאו": "Clio", "קפצ'ור": "Captur", "קורולה": "Corolla", "יאריס": "Yaris",
        "קאמרי": "Camry", "פריוס": "Prius", "בירלנגו": "Berlingo", "זפירה": "Zafira", "אסטרה": "Astra", "קורסה": "Corsa",
        "איי 30": "i30", "טוסון": "Tucson", "ספורטאז'": "Sportage", "פיקנטו": "Picanto", "ריו": "Rio", "סיד": "Ceed",
        "סוויפט": "Swift", "ויטרה": "Vitara", "מאזדה 3": "Mazda 3", "סיוויק": "Civic", "ג'אז": "Jazz", "פוקוס": "Focus",
    ]
    private static func latin(_ text: String) -> String {
        if let whole = brandNames[text.trimmingCharacters(in: .whitespaces)] { return whole }
        return text.split(separator: " ").map { brandNames[String($0)] ?? String($0) }.joined(separator: " ")
    }

    private static func lot(_ s: ShopSource, _ lang: ShopLang) async throws -> Shop {
        async let cars: [Car] = rows(s, "cars?select=*")
        async let settings: [Lot] = rows(s, "lot_settings?select=*&limit=1")
        let (c, st) = try await (cars, settings)
        let set = st.first
        let he = lang == .he
        func clean(_ v: String?) -> String? { v.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
        // the lot's own words, as its website writes them
        let bodies: [String: (String, String)] = [
            "sedan": ("سيدان", "סדאן"), "hatchback": ("هاتشباك", "האצ'בק"), "suv": ("جيب", "פנאי-שטח"),
            "crossover": ("كروس أوفر", "קרוסאובר"), "wagon": ("ستيشن", "סטיישן"), "coupe": ("كوبيه", "קופה"),
            "convertible": ("مكشوفة", "קבריולט"), "mpv": ("ميني فان", "מיני-ואן"), "pickup": ("تندر", "טנדר"),
            "van": ("فان", "ואן"), "commercial": ("تجارية", "מסחרי")]
        let gears = ["auto": ("أوتوماتيك", "אוטומטית"), "manual": ("جير عادي", "ידנית")]
        let fuels = ["petrol": ("بنزين", "בנזין"), "hybrid": ("هايبرد", "היברידי"), "electric": ("كهربا", "חשמלי"),
                     "diesel": ("سولار", "דיזל"), "plugin": ("بلاج إن", "פלאג-אין")]
        func word(_ t: (String, String)?) -> String? { t.map { he ? $0.1 : $0.0 } }
        // sold cars stay on show for as many days as the lot chose, the newest sale first
        let keepDays = Double(set?.sold_visible_days ?? 7)
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let shown = c.filter { car in
            guard car.status == "sold" else { return true }
            guard let at = car.sold_at.flatMap({ iso.date(from: $0) }) else { return false }
            return Date.now.timeIntervalSince(at) < keepDays * 86_400
        }
        .sorted { a, b in
            if (a.status == "sold") != (b.status == "sold") { return b.status == "sold" }
            if a.status == "sold" { return (a.sold_at ?? "") > (b.sold_at ?? "") }
            if (a.featured ?? false) != (b.featured ?? false) { return a.featured ?? false }
            if (a.position ?? 0) != (b.position ?? 0) { return (a.position ?? 0) < (b.position ?? 0) }
            return (a.created_at ?? "") > (b.created_at ?? "")
        }
        let num = NumberFormatter(); num.numberStyle = .decimal; num.locale = Locale(identifier: "en_US")
        let items = shown.map { car -> Shop.Item in
            // a make or model kept in Hebrew is shown by its brand name outside Hebrew, so a screen keeps one language
            let name = he ? "\(car.make) \(car.model)" : "\(latin(car.make)) \(latin(car.model))"
            let plate = String(format: "%03d", car.stock_no)
            let photos = (car.photos ?? []).compactMap(URL.init(string:))
            let link = s.site.map { $0.appendingPathComponent("car/\(car.id)").absoluteString } ?? ""
            var facts: [String] = [String(car.year)]
            if let km = car.km { facts.append((num.string(from: NSNumber(value: km)) ?? String(km)) + (he ? " ק\"מ" : " كم")) }
            if let hand = car.hand { facts.append((he ? "יד " : "إيد ") + String(hand)) }
            if let g = word(car.gearbox.flatMap { gears[$0] }) { facts.append(g) }
            if let f = word(car.fuel.flatMap { fuels[$0] }) { facts.append(f) }
            if let col = clean(he ? car.color_he : car.color_ar) { facts.append(col) }
            return Shop.Item(
                id: car.id, categories: ["*"] + [car.body ?? ""].filter { !$0.isEmpty } + (car.status == "sold" ? ["sold"] : []),
                name: name, line: clean(car.trim).map { "\($0) · \(car.year)" } ?? String(car.year),
                note: clean(he ? car.notes_he : car.notes_ar),
                price: car.price.map(Double.init), sizes: nil,
                image: photos.first, available: car.status != "sold",
                badge: car.prev_price != nil && car.price != nil && car.prev_price! > car.price! ? (he ? "ירד מחיר" : "نزل السعر") : nil,
                tags: facts, detail: "#" + plate, gallery: photos.count > 1 ? photos : nil,
                ask: he ? "שלום, לגבי \(name) \(car.year) (מספר \(plate)), עדיין זמין?\n\(link)"
                        : "مرحبا، بسأل عن \(name) \(car.year) (رقم \(plate))، لسا متوفرة؟\n\(link)")
        }
        let available = shown.filter { $0.status != "sold" }
        let usedBodies = bodies.keys.filter { b in available.contains { $0.body == b } }
            .sorted { a, b in available.filter { $0.body == a }.count > available.filter { $0.body == b }.count }
        var cats = [Shop.Category(id: "*", name: L("הכל", in: lang.ui), subtitle: nil, image: nil)]
        cats += usedBodies.map { Shop.Category(id: $0, name: word(bodies[$0]) ?? $0, subtitle: nil, image: nil) }
        if shown.contains(where: { $0.status == "sold" }) { cats.append(Shop.Category(id: "sold", name: he ? "נמכרו" : "انباعت", subtitle: nil, image: nil)) }
        let window = available.filter { $0.featured == true } + available.filter { $0.featured != true }
        let pay = (he ? set?.payment_he : set?.payment_ar) ?? []
        return Shop(
            name: clean(he ? set?.name_he : set?.name_ar) ?? clean(set?.name_ar) ?? "",
            tagline: clean(he ? set?.tagline_he : set?.tagline_ar),
            logo: s.logo, heroes: [], categories: cats, items: items,
            featured: window.prefix(6).map(\.id),
            note: pay.isEmpty ? nil : pay.joined(separator: " · "),
            fetched: .now)
    }

    private static func rows<T: Decodable>(_ s: ShopSource, _ query: String) async throws -> [T] {
        var req = URLRequest(url: URL(string: s.base.absoluteString + "/rest/v1/" + query)!)
        req.setValue(s.key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(s.key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode([T].self, from: data)
    }

    private static func file(_ id: Int, _ lang: ShopLang) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("shop2-\(id)-\(lang.rawValue).json")
    }
}
