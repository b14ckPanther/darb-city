import SwiftUI

/// Darb's management, native: the partners' loyalty offers (make, pause, invite their staff) and coverage, town
/// by town. Only Darb's admins see it; the server checks every call again.
struct AdminView: View {
    enum Section: Hashable { case loyalty, coverage }
    @State private var section: Section = .loyalty

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                Text(L("הטבות")).tag(Section.loyalty)
                Text(L("כיסוי")).tag(Section.coverage)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 8)
            switch section {
            case .loyalty: LoyaltyAdmin()
            case .coverage: CoverageAdmin()
            }
        }
        .background(Color.canvas)
        .page(L("ניהול"))
    }
}

// MARK: loyalty

private struct LoyaltyAdmin: View {
    @State private var offers: [LoyaltyOffer] = []
    @State private var loaded = false
    @State private var creating = false
    @State private var invite: URL?

    var body: some View {
        List {
            Section {
                Button { creating = true } label: { Label(L("הטבה חדשה"), systemImage: "plus.circle.fill").font(.darb(.body, .bold)) }
            }
            Section {
                if loaded && offers.isEmpty { Text(L("עוד אין הטבות")).foregroundStyle(.secondary) }
                ForEach(offers) { o in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pick(o.business.name)).font(.darb(.headline, .heavy))
                        Text("\(pick(o.title)) · \(pick(o.reward)) · \(L("%lld החתמות", o.goal))")
                            .font(.darb(.subheadline)).foregroundStyle(.secondary)
                        if !o.active { Text(L("מושהית")).font(.darb(.caption, .bold)).foregroundStyle(Color.shut) }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(o.active ? L("להשהות") : L("להפעיל")) { Task { try? await LoyaltyAPI.setActive(o.id, !o.active); await load() } }
                            .tint(o.active ? .orange : .green)
                    }
                    .contextMenu {
                        Button { Task { invite = try? await LoyaltyAPI.invite(o.business.id) } } label: {
                            Label(L("קישור הזמנה לצוות"), systemImage: "person.badge.plus")
                        }
                        Button { Task { try? await LoyaltyAPI.setActive(o.id, !o.active); await load() } } label: {
                            Label(o.active ? L("להשהות") : L("להפעיל"), systemImage: o.active ? "pause.circle" : "play.circle")
                        }
                    }
                }
            } header: {
                Text(L("הטבות"))
            } footer: {
                Text(L("לחיצה ארוכה על הטבה: קישור הזמנה לצוות של העסק. החלקה: השהיה."))
            }
        }
        .font(.darb(.body))
        .scrollContentBackground(.hidden)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $creating) { NewOfferSheet { await load() } }
        .sheet(item: $invite) { url in InviteSheet(url: url) }
    }

    private func load() async {
        offers = (try? await LoyaltyAPI.allOffers()) ?? offers
        loaded = true
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// The invite link, shown once: shared from here to the business's staff.
private struct InviteSheet: View {
    let url: URL
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.plus").font(.symbol(size: 40))
            Text(L("קישור הזמנה לצוות")).font(.darb(.title2, .black))
            Text(L("שלחו אותו לצוות של העסק. מי שפותח אותו מחובר יוכל להחתים כרטיסים. הוא תקף שבועיים ומוצג רק עכשיו."))
                .font(.darb(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            ShareLink(item: url) {
                Label(L("לשתף את הקישור"), systemImage: "square.and.arrow.up")
                    .font(.darb(.headline, .heavy)).foregroundStyle(Color.onColor)
                    .frame(maxWidth: .infinity).frame(height: 54).sticker(.mustard, radius: 18, line: 2.5, drop: 3)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

/// A new offer: find the business on Darb's server, then what earns a stamp, the reward and how many stamps.
private struct NewOfferSheet: View {
    let saved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var found: [AdminBusiness] = []
    @State private var business: AdminBusiness?
    @State private var title = ["he": "", "ar": "", "en": ""]
    @State private var reward = ["he": "", "ar": "", "en": ""]
    @State private var goal = 5
    @State private var cooldown = 180
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L("העסק")) {
                    if let business {
                        HStack { Text(pick(business.name)).font(.darb(.body, .bold)); Spacer(); Button(L("להחליף")) { self.business = nil } }
                    } else {
                        TextField(L("חיפוש עסק לפי שם"), text: $query)
                            .onChange(of: query) { _, q in Task { found = await AdminBusiness.search(q) } }
                        ForEach(found) { b in
                            Button { business = b } label: {
                                VStack(alignment: .leading) { Text(pick(b.name)).font(.darb(.body, .bold)); Text(b.placeSlug).font(.darb(.caption)).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section(L("על מה מקבלים החתמה")) { tri($title) }
                Section(L("ההטבה")) { tri($reward) }
                Section {
                    Stepper(L("%lld החתמות להטבה", goal), value: $goal, in: 2...20)
                    Stepper(L("%lld דקות בין החתמות", cooldown), value: $cooldown, in: 0...1440, step: 30)
                }
                if failed { Text(L("זה לא הצליח. נסו שוב.")).foregroundStyle(Color.shut) }
            }
            .font(.darb(.body))
            .navigationTitle(L("הטבה חדשה")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("ביטול")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("ליצור")) { Task { await save() } }
                        .disabled(business == nil || title["he"]!.isEmpty || reward["he"]!.isEmpty)
                }
            }
        }
    }

    private func tri(_ t: Binding<[String: String]>) -> some View {
        Group {
            TextField("עברית", text: Binding(get: { t.wrappedValue["he"] ?? "" }, set: { t.wrappedValue["he"] = $0 }))
            TextField("العربية", text: Binding(get: { t.wrappedValue["ar"] ?? "" }, set: { t.wrappedValue["ar"] = $0 }))
            TextField("English", text: Binding(get: { t.wrappedValue["en"] ?? "" }, set: { t.wrappedValue["en"] = $0 }))
                .environment(\.layoutDirection, .leftToRight)
        }
    }

    private func save() async {
        guard let business else { return }
        let clean = { (t: [String: String]) in t.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty } }
        do {
            _ = try await LoyaltyAPI.create(.init(businessId: business.id, title: clean(title), reward: clean(reward), goal: goal, cooldownMinutes: cooldown))
            await saved()
            dismiss()
        } catch { failed = true }
    }
}

/// A business as the admin's list sends it.
struct AdminBusiness: Decodable, Identifiable, Hashable {
    let id: String
    let slug: String
    let placeSlug: String
    let name: [String: String]

    static func search(_ q: String) async -> [AdminBusiness] {
        let q = q.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, var c = URLComponents(string: "admin/businesses") else { return [] }
        c.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: "8")]
        guard let path = c.string, let (data, status) = try? await DarbAPI.authorized(path), status == 200 else { return [] }
        struct Page: Decodable { let items: [AdminBusiness] }
        return (try? JSONDecoder().decode(Page.self, from: data).items) ?? []
    }
}

// MARK: coverage

/// Coverage, town by town: the nine boxes fill as each everyday need gets a real place.
private struct CoverageAdmin: View {
    struct Row: Decodable, Identifiable { let id: String; let slug: String; let name: [String: String]; let type: String; let status: String; let population: Int?; let businesses: Int; let needs: [String: Int] }
    @State private var rows: [Row] = []
    @State private var query = ""
    @State private var showDone = false
    private let order = ["food", "sweets", "coffee", "bakery", "pharmacy", "grocery", "fuel", "garage", "bank"]

    var body: some View {
        let shown = rows.filter { r in
            let c = order.filter { (r.needs[$0] ?? 0) > 0 }.count
            return (showDone || c < 9) && (query.isEmpty || r.slug.contains(query.lowercased()) || r.name.values.contains { $0.contains(query) })
        }
        List {
            Section {
                Toggle(L("להציג גם ישובים מכוסים"), isOn: $showDone)
            } footer: {
                Text(L("%lld ישובים מכוסים במלואם מתוך %lld", rows.filter { r in order.allSatisfy { (r.needs[$0] ?? 0) > 0 } }.count, rows.count))
            }
            ForEach(shown.prefix(150)) { r in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(pick(r.name)).font(.darb(.headline, .heavy))
                        Spacer()
                        Text(L("%lld עסקים", r.businesses)).font(.darb(.caption, .bold)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        ForEach(Array(order.enumerated()), id: \.offset) { i, need in
                            let n = r.needs[need] ?? 0
                            Need.all.first { $0.key == need }.map { ArtImage(name: $0.art, small: true).frame(width: 26, height: 26) }
                                .frame(width: 30, height: 30)
                                .background(n > 0 ? Color.mustard : Color.card2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .opacity(n > 0 ? 1 : 0.45)
                                .accessibilityLabel("\(need) \(n)")
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.vertical, 4)
            }
        }
        .font(.darb(.body))
        .scrollContentBackground(.hidden)
        .searchable(text: $query, prompt: L("חיפוש ישוב"))
        .task {
            guard let (data, status) = try? await DarbAPI.authorized("admin/coverage"), status == 200 else { return }
            rows = (try? JSONDecoder().decode([Row].self, from: data)) ?? []
        }
    }
}
