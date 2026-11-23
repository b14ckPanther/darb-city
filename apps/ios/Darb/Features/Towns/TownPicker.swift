import SwiftUI

/// Towns that have this kind of place, grouped by how far they are.
struct TownPicker: View {
    @Environment(Store.self) private var store
    let title: String
    let color: Color
    let entries: [Entry]
    let selected: String?
    let pick: (String?) -> Void

    private struct Town: Identifiable { let slug: String; var n: Int; var open: Int; var min: Int; var id: String { slug } }
    private static let bands: [(String, ClosedRange<Int>)] = [(L("עד 10 דקות"), 0...9), (L("10 עד 20 דקות"), 10...19), (L("מעל 20 דקות"), 20...999)]

    private var towns: [Town] {
        var t: [String: Town] = [:]
        for e in entries {
            var x = t[e.business.place] ?? Town(slug: e.business.place, n: 0, open: 0, min: 999)
            x.n += 1; x.open += e.status.isOpen ? 1 : 0; x.min = Swift.min(x.min, e.business.minutes)
            t[e.business.place] = x
        }
        return t.values.sorted { ($0.min, $0.slug) < ($1.min, $1.slug) }
    }

    var body: some View {
        let all = towns
        VStack(spacing: 0) {
            HStack {
                Text(L("איפה לחפש %@?", title)).font(.darb(.title2, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Button { pick(selected) } label: {
                    Image(systemName: "xmark").font(.symbol(.footnote))
                        .frame(width: 32, height: 32).background(Color.card2, in: Circle())
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(PressStyle(scale: 0.9))
                .accessibilityLabel(L("סגירה"))
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Button { pick(nil) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "location.fill").font(.symbol(.subheadline))
                                .foregroundStyle(color)
                                .frame(width: 38, height: 38).background(Color.onColor, in: Circle())
                            VStack(alignment: .leading, spacing: 0) {
                                Text(L("קרוב אליי")).font(.darb(.headline, .heavy))
                                Text(L("הכי קרובים, מכל הישובים")).font(.darb(.caption, .semibold)).opacity(0.7)
                            }
                            Spacer()
                            if selected == nil { Image(systemName: "checkmark").font(.symbol(.subheadline)) }
                        }
                        .foregroundStyle(Color.onColor)
                        .padding(.horizontal, 10)
                        .frame(height: 58)
                        .background(ColorField(color: color).clipShape(Capsule()))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle(scale: 0.98))
                    .accessibilityAddTraits(selected == nil ? .isSelected : [])
                    ForEach(Self.bands.indices, id: \.self) { i in
                        let inBand = all.filter { Self.bands[i].1.contains($0.min) }
                        if !inBand.isEmpty {
                            Text(Self.bands[i].0).font(.darb(.caption, .bold)).foregroundStyle(.secondary).padding(.top, 8).padding(.horizontal, 4)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                                ForEach(inBand) { t in town(t) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .background(Color.canvas)
        .foregroundStyle(Color.ink)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }

    private func town(_ t: Town) -> some View {
        let on = t.slug == selected
        return Button { pick(t.slug) } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.placeName(t.slug)).font(.darb(.subheadline, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 4) {
                        Circle().fill(t.open > 0 ? (on ? Color(hex: 0x3DDC97) : Color.open) : Color.shut).frame(width: 6, height: 6)
                        Text(t.open > 0 ? L("%lld פתוחים · %lld דק׳", t.open, t.min) : L("סגור · %lld דק׳", t.min)).font(.darb(.caption, .medium)).opacity(0.7).lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                Text(verbatim: "\(t.n)").font(.figure(.title3, weight: .heavy))
            }
            .padding(.horizontal, 14).frame(height: 58)
            .foregroundStyle(on ? Color.canvas : Color.ink)
            .background(on ? Color.ink : Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(L("%@, %lld מקומות", store.placeName(t.slug), t.n) + ", " + (t.open > 0 ? L("%lld פתוחים", t.open) : L("סגור היום")))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
