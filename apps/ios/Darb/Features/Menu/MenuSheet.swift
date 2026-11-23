import SwiftUI

/// A page of the menu.
enum MenuPage: Hashable {
    case settings, saved, plans, about, town, fonts
    /// Signing in for staff; stamping at the counter; Darb's management.
    case account, stamp, admin
    case join(plan: String?)
    case contact(topic: DarbAPI.Inquiry.Topic, plan: String?)
    case legal(LegalKind)

    /// `-darbSheet settings` and the like, for screenshots and tests.
    init?(argument: String) {
        switch argument {
        case "settings": self = .settings
        case "saved": self = .saved
        case "plans": self = .plans
        case "about": self = .about
        case "join": self = .join(plan: nil)
        case "contact": self = .contact(topic: .general, plan: nil)
        case "terms": self = .legal(.terms)
        case "privacy": self = .legal(.privacy)
        case "fonts": self = .fonts
        case "account": self = .account
        case "stamp": self = .stamp
        case "admin": self = .admin
        default: return nil
        }
    }
}

/// Opening the menu: on its front, or straight on one of its pages.
struct MenuStart: Identifiable {
    let page: MenuPage?
    let id = UUID()
    init(_ page: MenuPage?) { self.page = page }
}

/// The rest of the app behind one button: the language, where you are, what you kept, the settings,
/// and for a business owner the plans, joining and a way to write to Darb. Every page opens inside it.
struct MenuSheet: View {
    @State private var account = Account.shared
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Opens a place on the home screen's own stack, after the menu has closed.
    let open: (Route) -> Void
    @State private var path: [MenuPage]

    init(start: MenuPage?, open: @escaping (Route) -> Void) {
        self.open = open
        _path = State(initialValue: start.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            front
                .navigationDestination(for: MenuPage.self) { page in
                    Group {
                        switch page {
                        case .settings: SettingsView(path: $path)
                        case .saved: SavedList { open(.business($0.business.id)) }
                        case .plans: PlansView(path: $path)
                        case .about: AboutView(path: $path)
                        case .town: TownList { path.removeLast() }.page(L("ישוב ומיקום"))
                        case .fonts: FontsView()
                        case .account: SignInView { path.append($0) }
                        case .stamp: StampView()
                        case .admin: AdminView()
                        case .join(let plan): JoinForm(plan: plan)
                        case .contact(let topic, let plan): ContactForm(topic: topic, plan: plan)
                        case .legal(let kind): LegalView(kind: kind)
                        }
                    }
                    .onAppear { Perf.shown(MenuSheet.perfName(page)) }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { dismiss() } label: { Image(systemName: "xmark").font(.symbol(.subheadline)) }.accessibilityLabel(L("סגירה"))
                        }
                    }
                }
        }
        // a new language redraws every page, and the stack keeps its place
        .id(store.lang)
        .environment(\.layoutDirection, store.lang.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, store.lang.locale)
        .tint(Color.ink)
        .foregroundStyle(Color.ink)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    /// The name `-darbSheet` opens a page by, for timing it.
    static func perfName(_ page: MenuPage) -> String {
        switch page {
        case .settings: "settings"
        case .saved: "saved"
        case .plans: "plans"
        case .about: "about"
        case .town: "town"
        case .fonts: "fonts"
        case .join: "join"
        case .contact: "contact"
        case .legal(let k): k.rawValue
        case .account: "account"
        case .stamp: "stamp"
        case .admin: "admin"
        }
    }

    /// The menu's front: a native inset list, so it scrolls, highlights and reads the way iOS does, dressed in
    /// Darb's own type and colours. The header is a sticker of the mark; each row carries its icon on a small
    /// coloured sticker.
    private var front: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        Image("Mark").resizable().scaledToFit().frame(width: 34, height: 34)
                            .frame(width: 62, height: 62)
                            .sticker(Color.onColor, radius: 20)
                            .rotationEffect(.degrees(-4))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("דרב")).font(.poster(44, relativeTo: .largeTitle))
                            Text(L("web.messages.tagline")).font(.darb(.caption, .medium)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    LanguageSwitch()
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }
            Section {
                Button { path.append(.town) } label: {
                    row(store.isLive ? "location.fill" : "mappin.and.ellipse", Color(hex: 0x2FCF86), L("ליד %@", store.homeName),
                        store.isLive ? L("לפי המיקום שלכם") : store.outside ? L("אתם מחוץ לאזור של דרב, אז לפי הישוב שבחרתם") : L("לפי ישוב שבחרתם"))
                }
                .listRowBackground(Color.card)
            }
            Section(L("שלי")) {
                WalletCardRow().listRowBackground(Color.card)
                link(.saved, "bookmark.fill", Color(hex: 0xFF7FBE), L("מקומות ששמרתי"), store.saved.isEmpty ? L("עוד לא שמרתם מקום") : L("%lld מקומות", store.saved.count))
                link(.settings, "gearshape.fill", Color(hex: 0x66CCFF), L("הגדרות"), L("שפה, מראה, התראות וניווט"))
            }
            if Account.available {
                Section(L("צוות")) {
                    if account.step == .signedIn {
                        link(.stamp, "qrcode.viewfinder", Color(hex: 0x3DDC97), L("החתמת כרטיס"), L("סריקה במצלמה, החתמה בנגיעה"))
                    }
                    if account.isAdmin {
                        link(.admin, "slider.horizontal.3", Color(hex: 0x66CCFF), L("ניהול"), L("הטבות, קישורי צוות וכיסוי לפי ישוב"))
                    }
                    link(.account, "person.crop.circle.fill", Color(hex: 0xB79CFF), account.step == .signedIn ? (account.email ?? L("מחוברים")) : L("כניסה לצוות"),
                         account.step == .signedIn ? L("מחוברים") : L("לצוות של דרב ושל העסקים השותפים"))
                }
            }
            Section(L("לבעלי עסקים")) {
                link(.plans, "rectangle.stack.fill", .mustard, L("תוכניות ומחירים"), store.paidFrom.map { L("רישום בחינם, ותוכניות מ ₪%lld לחודש", $0) })
                link(.join(plan: nil), "storefront.fill", Color(hex: 0xFF9A2E), L("web.landing.join.list"), L("כמה דקות, ובלי תשלום"))
            }
            Section(L("דרב")) {
                link(.contact(topic: .general, plan: nil), "envelope.fill", Color(hex: 0xB79CFF), L("web.messages.contactUs"), L("אדם אמיתי קורא כל הודעה"))
                link(.about, "signpost.right.fill", Color(hex: 0xC8F03C), L("על דרב"), nil)
                link(.legal(.terms), "doc.text.fill", Color(hex: 0xF2EBE0), L("תנאי שימוש"), nil)
                link(.legal(.privacy), "hand.raised.fill", Color(hex: 0xF2EBE0), L("פרטיות"), nil)
            }
            Section {
                Text(verbatim: L("גרסה %@", Bundle.main.version)).font(.darb(.caption)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .listSectionSpacing(18)
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .font(.darb(.body))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(L("סגירה"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Perf.shown("menu") }
    }

    /// A row: its icon on a small sticker of its own colour, a title and a line under it.
    private func row(_ symbol: String, _ tint: Color, _ title: String, _ detail: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.symbol(size: 15)).foregroundStyle(Color.onColor)
                .frame(width: 34, height: 34)
                .sticker(tint, radius: 11, line: 2, drop: 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.darb(.body, .bold)).foregroundStyle(Color.ink)
                if let detail { Text(detail).font(.darb(.caption)).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.symbol(.caption)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func link(_ page: MenuPage, _ symbol: String, _ tint: Color, _ title: String, _ detail: String?) -> some View {
        Button { path.append(page) } label: { row(symbol, tint, title, detail) }
            .listRowBackground(Color.card)
    }
}

/// The three languages side by side, each written in its own letters. One touch changes the whole app.
struct LanguageSwitch: View {
    @Environment(Store.self) private var store
    var body: some View {
        Segments(options: Lang.allCases.map { (value: $0, title: $0.endonym, font: .darb(.subheadline, .bold, in: $0)) },
                 selection: Binding(get: { store.lang }, set: { store.setLang($0) }))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("web.messages.language"))
    }
}

/// The places the person kept.
struct SavedList: View {
    @Environment(Store.self) private var store
    let pick: (Entry) -> Void

    var body: some View {
        let kept = store.savedEntries
        ScrollView {
            if kept.isEmpty {
                Notice(symbol: "bookmark", title: L("עוד אין מקומות שמורים"), message: L("הסימנייה בראש כל עמוד שומרת את המקום כאן."))
                    .padding(.top, 40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(kept) { e in
                        Button { pick(e) } label: { ResultRow(entry: e) }
                            .buttonStyle(PressStyle(scale: 0.98))
                            .contextMenu { Button(role: .destructive) { store.toggleSaved(e.id) } label: { Label(L("להסיר מהשמורים"), systemImage: "bookmark.slash") } }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .page(L("מקומות ששמרתי"))
    }
}

extension Bundle {
    var version: String { (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "" }
}
