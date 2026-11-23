import Foundation
import os

/// What the app and its widget both remember: the language, the chosen town, the last known position.
enum Shared {
    static let group = "group.il.co.darb.app"
    /// The shared store when the app group is set up, and the app's own store otherwise.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: group) ?? .standard
}

/// The three languages Darb speaks. The person chooses one in the app; it does not follow the phone.
enum Lang: String, CaseIterable, Sendable, Codable, Identifiable {
    case he, ar, en

    var id: String { rawValue }
    var isRTL: Bool { self != .en }
    /// The language's own name, as its speakers write it.
    var endonym: String {
        switch self {
        case .he: "עברית"
        case .ar: "العربية"
        case .en: "English"
        }
    }
    /// Dates and numbers in this language. Figures stay Western digits in all three.
    var locale: Locale {
        switch self {
        case .he: Locale(identifier: "he_IL")
        case .ar: Locale(identifier: "ar_IL@numbers=latn")
        case .en: Locale(identifier: "en_IL")
        }
    }

    private static let key = "darbLang"
    private static let box = OSAllocatedUnfairLock<Lang>(initialState: Lang.stored())

    /// The language in use now. Everything that shows text reads it.
    static var current: Lang {
        get { box.withLock { $0 } }
        set {
            box.withLock { $0 = newValue }
            Shared.defaults.set(newValue.rawValue, forKey: key)
        }
    }

    /// The language the person chose, or on a first run the phone's own when it is one of the three.
    static func stored(in defaults: UserDefaults = Shared.defaults) -> Lang {
        // `-darbLang ar` sets the language for one run, for screenshots and tests
        if let forced = UserDefaults.standard.string(forKey: "darbLangOnce").flatMap(Lang.init(rawValue:)) { return forced }
        if let saved = defaults.string(forKey: key).flatMap(Lang.init(rawValue:)) { return saved }
        return fromPhone()
    }

    /// Whether the person has chosen a language yet.
    static var isChosen: Bool { Shared.defaults.string(forKey: key) != nil }

    static func fromPhone(_ preferred: [String] = Locale.preferredLanguages) -> Lang {
        for code in preferred {
            let base = code.split(separator: "-").first.map(String.init) ?? code
            if base == "iw" { return .he }
            if let l = Lang(rawValue: base) { return l }
        }
        return .he
    }

    /// Reads the saved language again; the widget does this before it draws.
    static func reload() { box.withLock { $0 = stored() } }
}

/// A text in the three languages, as the data carries it.
struct Tri: Sendable, Hashable, Decodable {
    let he: String
    let ar: String
    let en: String

    init(he: String, ar: String = "", en: String = "") {
        self.he = he
        self.ar = ar.isEmpty ? he : ar
        self.en = en.isEmpty ? he : en
    }
    /// The same text in all three, for a name that is not translated.
    init(_ all: String) { self.init(he: all) }

    private enum CodingKeys: String, CodingKey { case he, ar, en }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let he = try c.decodeIfPresent(String.self, forKey: .he) ?? ""
        self.init(he: he, ar: try c.decodeIfPresent(String.self, forKey: .ar) ?? "", en: try c.decodeIfPresent(String.self, forKey: .en) ?? "")
    }

    subscript(_ lang: Lang) -> String {
        switch lang {
        case .he: he
        case .ar: ar
        case .en: en
        }
    }
    /// The text in the language in use now.
    var now: String { self[Lang.current] }
    var isEmpty: Bool { he.isEmpty }
    /// All three in lower case, for searching in any language.
    var searchKey: String { he == ar && he == en ? he.lowercased() : "\(he)\n\(ar)\n\(en)".lowercased() }
}

/// Darb's copy lives in `Localizable.xcstrings`. A phrase the app wrote itself is keyed by its Hebrew;
/// a phrase taken from the website is keyed by where it lives there ("web.contact.form.name").
enum Strings {
    nonisolated(unsafe) private static let bundles: [Lang: Bundle] = {
        var out: [Lang: Bundle] = [:]
        for lang in Lang.allCases {
            if let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"), let b = Bundle(path: path) { out[lang] = b }
        }
        return out
    }()

    static func text(_ key: String, in lang: Lang) -> String {
        guard let b = bundles[lang] else { return key }
        return b.localizedString(forKey: key, value: key, table: nil)
    }

    /// Whether the catalog carries this key in this language.
    static func has(_ key: String, in lang: Lang) -> Bool {
        guard let b = bundles[lang] else { return false }
        return b.localizedString(forKey: key, value: "\u{1}", table: nil) != "\u{1}"
    }
}

/// The phrase in the language in use now. `%lld` takes a whole number and `%@` a text.
func L(_ key: String, _ args: CVarArg...) -> String {
    let lang = Lang.current
    let text = Strings.text(key, in: lang)
    return args.isEmpty ? text : String(format: text, locale: lang.locale, arguments: args)
}

/// The same, in a language you name.
func L(_ key: String, in lang: Lang, _ args: CVarArg...) -> String {
    let text = Strings.text(key, in: lang)
    return args.isEmpty ? text : String(format: text, locale: lang.locale, arguments: args)
}
