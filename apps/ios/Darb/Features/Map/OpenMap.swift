import MapKit
import SwiftUI

/// The places open around you, on a map: each one a small sticker in its need's colour, the nearest ones first.
/// A row of needs along the top narrows it to one. Touching a place opens its page.
struct OpenMap: View {
    @Environment(Store.self) private var store
    let open: (Route) -> Void
    @State private var need: String?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var picked: Int?

    var body: some View {
        let places = shown
        Map(position: $camera, selection: $picked) {
            UserAnnotation()
            ForEach(places, id: \.id) { b in
                let n = Need.forKind(b.kind)
                Annotation(b.name, coordinate: CLLocationCoordinate2D(latitude: b.lat, longitude: b.lng), anchor: .bottom) {
                    Pin(art: store.art(for: b).render ?? n?.art, color: n?.color ?? .mustard, big: picked == b.id)
                }
                .annotationTitles(.hidden)
                .tag(b.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass(); MapPitchToggle() }
        .safeAreaInset(edge: .top, spacing: 0) { filters }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let id = picked, let b = store.business(id) { card(b).transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: picked)
        .onAppear {
            let o = store.origin
            camera = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: o.lat, longitude: o.lng), latitudinalMeters: 3500, longitudinalMeters: 3500))
        }
    }

    /// The nearest open places, of one need when one is picked: few enough that the map stays quick.
    private var shown: [Business] {
        let kinds = need.flatMap(Need.byKey)?.kinds
        return Array(store.near.lazy.filter { b in (kinds?.contains(b.kind) ?? (Need.forKind(b.kind) != nil)) && store.status(b).isOpen }.prefix(150))
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(nil, L("הכל"), nil)
                ForEach(Need.all) { n in chip(n.key, n.short, n.color) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ key: String?, _ title: String, _ color: Color?) -> some View {
        let on = need == key
        return Button { withAnimation(.snappy) { need = key; picked = nil }; Haptic.tap() } label: {
            Text(title).font(.poster(20, relativeTo: .headline))
                .padding(.horizontal, 14).frame(height: 36)
                .foregroundStyle(on ? Color(hex: 0xFBF7EC) : Color.onColor)
                .sticker(on ? Color.onColor : (color ?? Color(hex: 0xFBF7EC)), radius: 18, line: 2, drop: on ? 1 : 3)
        }
        .buttonStyle(PressStyle(scale: 0.95))
    }

    private func card(_ b: Business) -> some View {
        let e = store.entry(b)
        return Button { open(.business(b.id)) } label: {
            HStack(spacing: 12) {
                ArtImage(name: store.art(for: b).render ?? Need.forKind(b.kind)?.art ?? "p-plate", small: true).frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.name).font(.poster(26, relativeTo: .title3)).lineLimit(1)
                    Text(e.status.text).font(.darb(.caption, .bold)).opacity(0.75)
                }
                Spacer(minLength: 0)
                SignDigits(text: String(format: "%02d", min(99, b.minutes)), size: 18, lit: e.status.isOpen)
                Text(L("דק׳")).font(.darb(.caption, .heavy))
            }
            .padding(12)
            .foregroundStyle(Color.onColor)
            .sticker(Need.forKind(b.kind)?.color ?? .mustard, radius: 22)
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

/// A place on the map: its object on a small outlined disc of its need's colour, larger when picked.
private struct Pin: View {
    let art: String?
    let color: Color
    let big: Bool
    var body: some View {
        let s: CGFloat = big ? 50 : 32
        ZStack {
            Circle().fill(color)
            if let art { ArtImage(name: art, small: true).padding(s * 0.12) }
        }
        .frame(width: s, height: s)
        .overlay { Circle().strokeBorder(Color.onColor, lineWidth: big ? 3 : 2) }
        .background { Circle().fill(Color.onColor).offset(y: 2) }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: big)
    }
}
