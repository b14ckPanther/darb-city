import SwiftUI

enum LegalKind: String, Hashable, Sendable { case terms, privacy }

/// The terms and the privacy policy as the website has them (apps/web/src/content/legal.ts),
/// written into the bundle by scripts/sync-copy.mjs and drawn here, not opened in a browser.
struct Legal: Decodable, Sendable {
    struct Block: Decodable, Sendable, Hashable { let text: String?; let list: [String]? }
    struct Section: Decodable, Sendable, Identifiable { let id: String; let title: String; let blocks: [Block] }
    struct Doc: Decodable, Sendable { let title: String; let lead: String; let sections: [Section] }
    struct Chrome: Decodable, Sendable { let contents: String; let updated: String }

    let updated: String
    let email: String
    let chrome: [String: Chrome]
    let docs: [String: [String: Doc]]

    static func load(from bundle: Bundle = .main) -> Legal? {
        guard let url = bundle.url(forResource: "legal", withExtension: "json"), let raw = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Legal.self, from: raw)
    }

    func doc(_ kind: LegalKind, in lang: Lang) -> Doc? { docs[kind.rawValue]?[lang.rawValue] ?? docs[kind.rawValue]?["he"] }
}

struct LegalView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let kind: LegalKind
    @State private var legal = Legal.load()

    var body: some View {
        let doc = legal?.doc(kind, in: store.lang)
        ScrollViewReader { proxy in
            ScrollView {
                if let legal, let doc {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(doc.title).display(30, relativeTo: .title)
                            Text(doc.lead).font(.darb(.subheadline)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Text(verbatim: (legal.chrome[store.lang.rawValue]?.updated ?? "") + ": " + date(legal.updated))
                                .font(.darb(.caption, .semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                        // the contents, each line a jump to its part
                        VStack(alignment: .leading, spacing: 0) {
                            Text(legal.chrome[store.lang.rawValue]?.contents ?? "").font(.darb(.caption, .bold)).foregroundStyle(.secondary).padding(.bottom, 4)
                            ForEach(Array(doc.sections.enumerated()), id: \.element.id) { i, s in
                                Button { withAnimation(Motion.land) { proxy.scrollTo(s.id, anchor: .top) } } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(verbatim: "\(i + 1)").font(.figure(.footnote, weight: .medium)).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
                                        Text(s.title).font(.darb(.subheadline, .semibold)).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressStyle(scale: 0.985))
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surface(radius: Radius.tile)
                        ForEach(doc.sections) { s in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(s.title).font(.darb(.headline, .heavy)).accessibilityAddTraits(.isHeader)
                                ForEach(Array(s.blocks.enumerated()), id: \.offset) { _, b in
                                    if let t = b.text { Text(t).font(.darb(.footnote)).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
                                    if let list = b.list {
                                        ForEach(list, id: \.self) { item in
                                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                Circle().fill(Color.ink.opacity(0.4)).frame(width: 4, height: 4).offset(y: -3)
                                                Text(item).font(.darb(.footnote)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 4).padding(.top, 8)
                            .id(s.id)
                        }
                        Button { if let u = URL(string: "mailto:" + legal.email) { openURL(u) } } label: {
                            MenuRow(symbol: "envelope.fill", title: legal.email, detail: L("לשאלות על המסמך הזה")) { EmptyView() }
                                .padding(.horizontal, 14).surface(radius: Radius.tile)
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .environment(\.layoutDirection, store.lang.isRTL ? .rightToLeft : .leftToRight)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 6)
                } else {
                    Notice(symbol: "doc.text", title: L("המסמך לא נטען"), message: nil).padding(.top, 40)
                }
            }
        }
        .page(doc?.title ?? "")
    }

    private func date(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Jerusalem")
        guard let d = f.date(from: iso) else { return iso }
        return d.formatted(.dateTime.day().month(.wide).year().locale(store.lang.locale))
    }
}

/// What Darb is, in its own words from the website, the real clients, where the data comes from, and the small print.
struct AboutView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Binding var path: [MenuPage]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Image("Mark").resizable().scaledToFit().frame(width: 34, height: 34)
                        .frame(width: 62, height: 62)
                        .background(Color.onColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)
                    Text(verbatim: L("web.landing.hero.title") + " " + L("web.landing.hero.accent")).display(32, relativeTo: .title).fixedSize(horizontal: false, vertical: true)
                    Text(L("web.messages.tagline")).font(.darb(.subheadline, .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("web.landing.story.eyebrow")).eyebrow().foregroundStyle(Color.gold)
                    ForEach(0..<4, id: \.self) { i in
                        let key = "web.landing.story.paragraphs.\(i)"
                        if Strings.has(key, in: store.lang) { Text(L(key)).font(.darb(.subheadline)).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(radius: Radius.card)

                GroupTitle(L("מאיפה המידע"))
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("%lld עסקים אמיתיים ב %lld ישובים, ממקורות ציבוריים פתוחים. אין כאן עסק מומצא.", store.all.count, store.data.places.count))
                        .font(.darb(.footnote)).fixedSize(horizontal: false, vertical: true)
                    Text(L("כשהשעות עוד לא אושרו על ידי העסק, זה כתוב בלשונית השעות שלו, וכדאי לשאול לפני שנוסעים."))
                        .font(.darb(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(radius: Radius.tile)

                GroupTitle(L("עוד"))
                RowGroup {
                    Button { openURL(DarbAPI.instagram) } label: {
                        MenuRow(symbol: "camera.fill", title: L("דרב באינסטגרם"), detail: nil) { Image(systemName: "arrow.up.forward").font(.symbol(.caption)).foregroundStyle(.tertiary) }
                    }
                    .buttonStyle(PressStyle(scale: 0.985))
                    link(.contact(topic: .general, plan: nil), "envelope.fill", L("web.messages.contactUs"))
                    link(.legal(.terms), "doc.text.fill", L("תנאי שימוש"))
                    link(.legal(.privacy), "hand.raised.fill", L("פרטיות"))
                    link(.fonts, "textformat", L("הגופנים והרישיונות שלהם"))
                }
                Text(verbatim: L("גרסה %@", Bundle.main.version)).font(.darb(.caption)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 6)
        }
        .page(L("על דרב"))
    }

    private func link(_ page: MenuPage, _ symbol: String, _ title: String) -> some View {
        Button { path.append(page) } label: { MenuRow(symbol: symbol, title: title) }
            .buttonStyle(PressStyle(scale: 0.985))
    }
}

/// The three typefaces and the licences they come with. Each licence asks to travel with the font.
struct FontsView: View {
    private static let faces: [(name: String, lang: Lang, licence: String, file: String)] = [
        ("Heebo", .he, "SIL Open Font License 1.1", "Heebo-OFL"),
        ("Cairo", .ar, "SIL Open Font License 1.1", "Cairo-OFL"),
        ("Ubuntu", .en, "Ubuntu Font Licence 1.0", "Ubuntu-UFL"),
    ]
    @State private var open: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.faces, id: \.name) { f in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: f.name).font(.darb(.title2, .bold, in: f.lang))
                            Spacer()
                            // the face in its own script, saying Darb's own line
                            Text(verbatim: L("web.landing.hero.title", in: f.lang)).font(.darb(.subheadline, .medium, in: f.lang)).foregroundStyle(.secondary)
                        }
                        Text(verbatim: f.licence).font(.figure(.footnote, weight: .medium)).foregroundStyle(.secondary)
                        Button { withAnimation(Motion.select) { open = open == f.file ? nil : f.file } } label: {
                            Text(open == f.file ? L("להסתיר את הרישיון") : L("לקרוא את הרישיון")).font(.darb(.footnote, .bold))
                                .padding(.horizontal, 12).frame(height: 32).background(Color.card2, in: Capsule()).frame(height: 44)
                        }
                        .buttonStyle(PressStyle(scale: 0.96))
                        if open == f.file, let url = Bundle.main.url(forResource: f.file, withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) {
                            Text(verbatim: text).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                                .environment(\.layoutDirection, .leftToRight)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surface(radius: Radius.tile)
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 6)
        }
        .page(L("הגופנים והרישיונות שלהם"))
    }
}
