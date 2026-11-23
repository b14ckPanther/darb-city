import Foundation

/// Reads a request in plain words: which kind, which town, and any name left over.
struct ParsedQuery: Equatable, Sendable {
    var kind: String?
    var place: String?
    var text: String
    var isEmpty: Bool { kind == nil && place == nil && text.isEmpty }
}

/// Everything search needs, made ready once and never changed: every word that means a kind or a town, and
/// one lower-case line per business with its name in the three languages. It is built off the main thread
/// soon after the app opens, and a request is read against it off the main thread too.
final class SearchIndex: Sendable {
    private let kindWords: [(slug: String, words: [String])]
    private let placeWords: [(slug: String, words: [String])]
    /// By position in the data: the business's kind and town, its names, and the line about it.
    private let kinds: [String]
    private let places: [String]
    private let names: [String]
    private let tags: [String]

    init(_ data: DarbData) {
        kindWords = data.kinds.map { k in (k.slug, k.words.filter { $0.count > 1 }.map { $0.lowercased() }) }
        placeWords = data.places.map { p in
            (p.slug, ([p.name.he, p.name.ar, p.name.en, Place.plain(p.name.he), Place.plain(p.name.ar)] + p.aliases).filter { $0.count > 1 }.map { $0.lowercased() })
        }
        kinds = data.businesses.map(\.kind)
        places = data.businesses.map(\.place)
        names = data.businesses.map { $0.names.searchKey }
        // most places share their line with many others, so each distinct line is lowered once
        var lowered: [String: String] = [:]
        tags = data.businesses.map { b in
            guard let t = b.tags else { return "" }
            if let known = lowered[t.he] { return known }
            let key = t.searchKey
            lowered[t.he] = key
            return key
        }
    }

    /// The little words that mean "in" before a town's name, in the three languages.
    private static let inWords = ["ב", "في ", "ب", "in ", "at "]

    /// Where a word stands in a text as a word of its own. In Latin letters it must not be part of a longer word;
    /// in the other two scripts a one-letter prefix before it is allowed, as people write "בכרמיאל".
    private static func find(_ word: String, in text: String) -> Range<String.Index>? {
        var from = text.startIndex
        while let r = text.range(of: word, range: from..<text.endIndex) {
            let latin = word.unicodeScalars.first.map { $0.value < 0x250 } ?? true
            let before = r.lowerBound > text.startIndex ? text[text.index(before: r.lowerBound)] : " "
            let after = r.upperBound < text.endIndex ? text[r.upperBound] : " "
            if latin {
                if !before.isLetter && !after.isLetter { return r }
            } else {
                // the start of a word, or one prefix letter after the start of a word
                let twoBack = r.lowerBound > text.startIndex && text.index(before: r.lowerBound) > text.startIndex
                    ? text[text.index(r.lowerBound, offsetBy: -2)] : " "
                if !before.isLetter || !twoBack.isLetter { return r }
            }
            from = text.index(after: r.lowerBound)
        }
        return nil
    }

    func parse(_ raw: String) -> ParsedQuery {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ParsedQuery(kind: nil, place: nil, text: "") }
        var kind: String?, kw = ""
        for k in kindWords {
            for word in k.words where word.count > kw.count && word.count <= q.count {
                if SearchIndex.find(word, in: q) != nil { kind = k.slug; kw = word }
            }
        }
        var rest = q
        if !kw.isEmpty, let r = SearchIndex.find(kw, in: q) { rest.replaceSubrange(r, with: " ") }
        var place: String?, pw = "", best = 0
        for p in placeWords {
            for word in p.words where word.count <= rest.count {
                guard let r = SearchIndex.find(word, in: rest) else { continue }
                let head = rest[..<r.lowerBound]
                let prefixed = SearchIndex.inWords.contains { head.hasSuffix($0) }
                let score = word.count + (prefixed ? 100 : 0)
                if score > best { best = score; place = p.slug; pw = word }
            }
        }
        var text = rest
        if !pw.isEmpty {
            for w in SearchIndex.inWords { text = text.replacingOccurrences(of: w + pw, with: " ") }
            text = text.replacingOccurrences(of: pw, with: " ")
        }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return ParsedQuery(kind: kind, place: place, text: text)
    }

    /// The businesses a request fits, by their position in the data, whatever their distance.
    func matches(_ p: ParsedQuery, within allowed: Set<String>?) -> [Int] {
        guard !p.isEmpty else { return [] }
        var out: [Int] = []
        for i in kinds.indices {
            if let k = p.kind, kinds[i] != k { continue }
            if let pl = p.place, places[i] != pl { continue }
            if let a = allowed, !a.contains(kinds[i]) { continue }
            if !p.text.isEmpty, !names[i].contains(p.text), !tags[i].contains(p.text) { continue }
            out.append(i)
        }
        return out
    }
}

extension Store {
    /// The index, built on the spot if the background has not delivered it yet.
    private func indexNow() -> SearchIndex {
        if let i = searchIndex { return i }
        let i = Perf.time("search.index") { SearchIndex(data) }
        searchIndex = i
        return i
    }

    func parse(_ raw: String) -> ParsedQuery { indexNow().parse(raw) }

    /// Open first, then nearest. A request that names a town looks in that town, however far; one that does not
    /// looks within driving distance first, and everywhere only if nothing is near.
    private func ranked(_ hits: [Int], for p: ParsedQuery, limit: Int) -> [Entry] {
        var found = p.place != nil ? hits : hits.filter { all[$0].km < maxKm }
        if found.isEmpty { found = hits }
        return found.map { entry(all[$0]) }
            .sorted { ($0.rank, $0.business.km) < ($1.rank, $1.business.km) }
            .prefix(limit).map { $0 }
    }

    /// Businesses matching a request, open first, then nearest.
    func search(_ raw: String, within kinds: [String]? = nil, limit: Int = 40) -> [Entry] {
        let index = indexNow()
        let p = index.parse(raw)
        return ranked(index.matches(p, within: kinds.map(Set.init)), for: p, limit: limit)
    }

    /// The same, with the reading and the matching done off the main thread, for searching while the person types.
    func searching(_ raw: String, within kinds: [String]? = nil, limit: Int = 60) async -> (read: ParsedQuery, results: [Entry]) {
        let index = indexNow()
        let allowed = kinds.map(Set.init)
        let (p, hits) = await Task.detached(priority: .userInitiated) {
            Perf.time("search.match") { let p = index.parse(raw); return (p, index.matches(p, within: allowed)) }
        }.value
        return (p, Perf.time("search.rank") { ranked(hits, for: p, limit: limit) })
    }
}
