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
        /// The amount in the pack, as printed.
        var detail: String? = nil
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
