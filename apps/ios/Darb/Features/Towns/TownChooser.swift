import SwiftUI
import UIKit

/// Where the app stands: the person's own position, or a town they choose from all of them.
/// Everything in the app (the valley, the tiles, the minutes, the order) is measured from here.
struct TownList: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    /// Called once the person has chosen.
    let done: () -> Void
    @State private var q = ""
    @FocusState private var typing: Bool

    var body: some View {
        let towns = store.towns(matching: q)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                locationCard
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.symbol(.body))
                    TextField(L("חיפוש עיר, עיירה או כפר"), text: $q)
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
                .frame(height: 50)
                .background(Color.card, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.ink.opacity(typing ? 0.5 : 0.1), lineWidth: typing ? 1.5 : 1) }
                .padding(.top, 6)
                Text(q.isEmpty ? L("כל הישובים, הקרובים קודם") : L("ישובים: %lld", towns.count))
                    .font(.darb(.caption, .bold)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.top, 6)
                if towns.isEmpty {
                    Notice(symbol: "magnifyingglass", title: L("web.join.check.noMatch"))
                }
                ForEach(towns) { p in row(p) }
            }
            .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 8)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.canvas)
        .foregroundStyle(Color.ink)
    }

    /// The location button, saying plainly what it does and what state it is in.
    private var locationCard: some View {
        let access = store.location.access
        let on = store.followsLocation
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(symbol: on && access == .allowed ? "location.fill" : "location", tint: Color.onColor.opacity(0.14), size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("web.near.useMyLocation")).font(.darb(.headline, .heavy))
                    Text(status(access: access, on: on)).font(.darb(.caption, .semibold)).opacity(0.72).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if on, access == .allowed, !store.outside { Image(systemName: "checkmark").font(.symbol(.subheadline)) }
            }
            if access == .denied {
                Button { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } } label: {
                    Text(L("לפתוח את ההגדרות")).font(.darb(.subheadline, .heavy))
                        .padding(.horizontal, 16).frame(height: 40)
                        .foregroundStyle(Color(hex: 0x3DDC97)).background(Color.onColor, in: Capsule())
                        .frame(height: 44)
                }
                .buttonStyle(PressStyle(scale: 0.96))
            }
        }
        .foregroundStyle(Color.onColor)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorField(color: .mustard).clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)))
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .onTapGesture {
            guard access != .denied else { return }
            Haptic.tap()
            store.followLocation()
            if access == .allowed { done() }
        }
        .onChange(of: store.location.access) { old, new in if old == .unasked, new == .allowed { done() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func status(access: LocationService.Access, on: Bool) -> String {
        switch access {
        case .denied: return L("web.near.denied")
        case .unasked: return L("web.near.ask")
        case .allowed:
            if !on { return L("web.near.ask") }
            if store.outside { return L("אתם מחוץ לאזור של דרב, אז התשובות לפי %@", store.placeName(store.town)) }
            if store.location.isLocating { return L("web.messages.locating") }
            return L("התשובות נמדדות מהמקום שבו אתם עומדים")
        }
    }

    private func row(_ p: Place) -> some View {
        let on = !store.isLive && p.slug == store.town
        let km = Geo.km(store.origin, lat: p.lat, lng: p.lng)
        return Button { Haptic.tap(); store.chooseTown(p.slug); done() } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.title).font(.darb(.subheadline, .bold)).lineLimit(1)
                    Text(kind(p.type)).font(.darb(.caption)).opacity(0.65)
                }
                Spacer(minLength: 6)
                if on { Image(systemName: "checkmark").font(.symbol(.subheadline)) }
                Text(Geo.distance(km)).font(.figure(.footnote, weight: .medium)).opacity(0.65)
            }
            .padding(.horizontal, 14).frame(height: 56)
            .foregroundStyle(on ? Color.canvas : Color.ink)
            .background(on ? Color.ink : Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.985))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func kind(_ type: String) -> String {
        switch type {
        case "city": L("עיר")
        case "town": L("עיירה")
        case "neighbourhood": L("שכונה")
        default: L("כפר או ישוב")
        }
    }
}

/// The same list as a sheet of its own, from the home screen's header.
struct TownChooser: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("איפה אתם?")).font(.darb(.title2, .heavy))
                Spacer()
                CloseButton { dismiss() }
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 4)
            TownList { dismiss() }
        }
        .background(Color.canvas)
        .foregroundStyle(Color.ink)
        .onAppear { Perf.shown("town") }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }
}
