import SwiftUI

/// Search in plain words: a name, a dish or a kind, and a town ("פיצה בכרמיאל").
/// As you type, Darb shows what it understood: the kind, the town, and the name left over.
struct SearchSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Only these kinds, when searching inside a need.
    let scope: [String]?
    var title: String? = nil
    /// Shown as the search tab, under Apple's own search field in the tab bar, instead of as a sheet with its own.
    var embedded = false
    let pick: (Entry) -> Void

    @State private var q = UserDefaults.standard.string(forKey: "darbQuery") ?? ""
    @FocusState private var typing: Bool
    /// What the last request found, and what Darb read in it. Worked out off the main thread while the person types.
    @State private var results: [Entry] = []
    @State private var read = ParsedQuery(kind: nil, place: nil, text: "")
    @State private var found = ""

    private var hints: [String] { [L("פיצה"), L("כספומט"), L("פז"), L("פלאפל"), L("מספרה"), L("בית מרקחת בכרמיאל"), L("מוסך בשפרעם")] }

    var body: some View {
        let text = q.trimmingCharacters(in: .whitespaces)
        VStack(spacing: 0) {
            if !embedded { header }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if text.isEmpty {
                        if scope == nil { suggestions } else { caption(L("%lld מקומות, הפתוחים והקרובים קודם", results.count)) }
                    } else {
                        understood
                        if found != text {
                            // the answer to what was just typed is on its way; the last one stays meanwhile
                            EmptyView()
                        } else if results.isEmpty {
                            Notice(symbol: "magnifyingglass", title: L("לא מצאנו את %@", text), message: L("אפשר לנסות שם אחר, או סוג וישוב, למשל מאפייה בעראבה."))
                                .padding(.top, 30)
                        } else {
                            caption(L("%lld תוצאות, הפתוחים והקרובים קודם", results.count))
                        }
                    }
                    ForEach(results) { e in
                        Button { pick(e) } label: {
                            if let look = DeluxeLook.of(e.business.id, lang: store.lang) { DeluxeResultCard(entry: e, look: look) } else { ResultRow(entry: e) }
                        }
                            .buttonStyle(PressStyle(scale: 0.98))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color.canvas)
        .foregroundStyle(Color.ink)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .onAppear { Perf.shown("search") }
        .onAppear { if !embedded, scope == nil || !q.isEmpty { typing = true } }
        .modifier(SystemSearch(on: embedded, q: $q))
        .task(id: q) {
            let text = q.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else {
                results = scope.map { store.entries(kinds: $0) } ?? []
                read = ParsedQuery(kind: nil, place: nil, text: "")
                found = ""
                return
            }
            let answer = await store.searching(q, within: scope, limit: 60)
            // a newer letter has been typed since: its own answer is coming
            guard !Task.isCancelled else { return }
            results = answer.results
            read = answer.read
            found = text
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(scope == nil ? L("חיפוש") : "כל \(title ?? "")").font(.darb(.title2, .heavy))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.symbol(.footnote))
                        .frame(width: 32, height: 32).background(Color.card2, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .accessibilityLabel(L("סגירה"))
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.symbol(.body))
                TextField(scope == nil ? L("שם של עסק, מנה או ישוב") : L("שם, או ישוב"), text: $q)
                    .focused($typing)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .font(.darb(.body, .medium))
                if !q.isEmpty {
                    Button { q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 30, height: 44) }
                        .accessibilityLabel(L("ניקוי"))
                }
            }
            .padding(.leading, 16).padding(.trailing, 10)
            .frame(height: 52)
            .background(Color.card, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.ink.opacity(typing ? 0.5 : 0.1), lineWidth: typing ? 1.5 : 1) }
            .animation(Motion.select, value: typing)
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 12)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.darb(.caption, .bold)).foregroundStyle(.secondary).padding(.top, 4).padding(.horizontal, 4)
    }

    /// What Darb read in the words: a kind, a town, a name.
    @ViewBuilder private var understood: some View {
        let p = read
        if p.kind != nil || p.place != nil {
            HStack(spacing: 6) {
                Text(L("הבנו")).font(.darb(.caption, .bold)).foregroundStyle(.secondary)
                if let k = p.kind { chip(store.kindName(k), "tag.fill") }
                if let pl = p.place { chip(store.placeName(pl), "mappin") }
                if !p.text.isEmpty { chip(p.text, "textformat") }
            }
            .padding(.horizontal, 4)
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        }
    }

    private func chip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.darb(.caption, .bold)).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.lamp.opacity(0.28), in: Capsule())
    }

    @ViewBuilder private var suggestions: some View {
        let kept = store.savedEntries
        if !kept.isEmpty {
            caption(L("מקומות ששמרתי"))
            ForEach(kept.prefix(3)) { e in
                Button { pick(e) } label: { ResultRow(entry: e) }.buttonStyle(PressStyle(scale: 0.98))
            }
        }
        caption(L("אפשר לכתוב כך"))
        Flow(spacing: 8) {
            ForEach(hints, id: \.self) { h in
                Button { q = h } label: {
                    Text(h).font(.darb(.subheadline, .semibold))
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(Color.card, in: Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.bottom, 6)
        // with nothing typed yet, the nearest open place for each need is already an answer
        caption(L("פתוחים, הכי קרוב"))
        ForEach(store.firsts().compactMap(\.entry).filter { $0.status.isOpen }.prefix(6)) { e in
            Button { pick(e) } label: { ResultRow(entry: e) }.buttonStyle(PressStyle(scale: 0.98))
        }
    }
}

/// A place in a list: what it is, whether it is open, and how far.
struct ResultRow: View {
    @Environment(Store.self) private var store
    let entry: Entry
    var body: some View {
        let b = entry.business
        HStack(spacing: 12) {
            ArtThumb(art: store.art(for: b))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(b.name).font(.darb(.body, .bold)).lineLimit(1)
                    if store.isPaid(store.profile(b.id)) { Image(systemName: "checkmark.seal.fill").font(.symbol(.caption)).foregroundStyle(Color.soon).accessibilityLabel(L("עמוד רשמי")) }
                }
                HStack(spacing: 5) {
                    StatusDot(status: entry.status, size: 6)
                    Text(verbatim: "\(entry.status.text) · \(store.kindName(b.kind)) · \(store.placeName(b.place))").lineLimit(1)
                }
                .font(.darb(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(spacing: -2) {
                Text(verbatim: "\(b.minutes)").font(.figure(.title3, weight: .heavy))
                Text(L("דק׳")).font(.darb(.caption2, .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 66)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .foregroundStyle(Color.ink)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The system's own search field, for the search tab: on iOS 26 it sits in the tab bar, in Liquid Glass.
private struct SystemSearch: ViewModifier {
    let on: Bool
    @Binding var q: String
    func body(content: Content) -> some View {
        if on {
            content
                .searchable(text: $q, prompt: Text(L("שם של עסק, מנה או ישוב")))
                .autocorrectionDisabled()
                .navigationTitle(L("חיפוש"))
        } else {
            content
        }
    }
}
