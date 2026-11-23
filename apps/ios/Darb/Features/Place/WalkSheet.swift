import CoreLocation
import MapKit
import SwiftUI

/// Walking to a place, inside the valley. The screen is the valley at this hour; in its sky a compass ring, with
/// the place's own object riding the ring towards where the place really is and a big arrow in the middle that turns
/// with the phone. Under it the distance counts down on a lit sign, and the next turn is said in words. A small map
/// keeps close on the person, turning with them. Arriving, the object jumps.
struct WalkSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let entry: Entry

    @State private var route: MKRoute?
    /// The straight distance when the route was worked out, to know how much the streets wind.
    @State private var routeStraight: Double = 1
    @State private var compass = Compass()
    @State private var routedFromLive = false
    @State private var arrivedHops = 0
    /// The small map stays close on the person, street level, turned the way they face.
    @State private var mapCamera: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)

    private var dest: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: entry.business.lat, longitude: entry.business.lng) }
    private var start: CLLocationCoordinate2D {
        compass.here?.coordinate ?? CLLocationCoordinate2D(latitude: store.origin.lat, longitude: store.origin.lng)
    }
    private var night: Bool { !store.looksDay }

    var body: some View {
        let b = entry.business
        let meters = CLLocation(latitude: start.latitude, longitude: start.longitude).distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
        let arrived = compass.here != nil && meters < 25
        // streets wind: the route's own ratio of walked to straight, else a quarter more; at 5 km an hour
        let wind = route.map { $0.distance / max(1, routeStraight) } ?? 1.25
        let minutes = max(1, Int((meters * min(2, max(1, wind)) / 83.3).rounded()))
        let turn = WalkSheet.bearing(start, dest) - (compass.heading ?? 0)
        let ink = night ? Color(hex: 0xFBF7EC) : Color.onColor
        GeometryReader { geo in
            ZStack {
                WalkValley(night: night)
                VStack(spacing: 0) {
                    // the top: close, and the place
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("ברגל אל")).font(.darb(.caption, .heavy)).opacity(0.7)
                            Text(b.name).font(.poster(34, relativeTo: .title)).lineLimit(1).minimumScaleFactor(0.6)
                            Text(entry.status.text).font(.darb(.caption, .bold)).opacity(0.75)
                        }
                        Spacer(minLength: 8)
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.symbol(.body)).frame(width: 44, height: 44).modifier(GlassTile())
                        }
                        .buttonStyle(PressStyle(scale: 0.92))
                        .accessibilityLabel(L("סגירה"))
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 20)
                    .padding(.top, geo.safeAreaInsets.top + 8)

                    Spacer(minLength: 8)
                    ring(turn: turn, arrived: arrived, size: min(geo.size.width * 0.74, 300))
                    Spacer(minLength: 8)

                    // how far, on the lit sign, and how long on foot
                    HStack(alignment: .center, spacing: 10) {
                        SignDigits(text: arrived ? "0" : Self.short(meters), size: 30, lit: true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(arrived ? L("הגעתם") : (meters >= 1000 ? L("ק״מ") : L("מטר"))).font(.darb(.headline, .heavy))
                            if !arrived { Text(L("%lld דק׳ ברגל", minutes)).font(.darb(.caption, .bold)).opacity(0.75) }
                        }
                    }
                    .foregroundStyle(ink)
                    .accessibilityElement(children: .combine)

                    if let step = nextStep, !arrived {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.up.left").font(.symbol(.title3)).foregroundStyle(Color.mustard)
                            Text(step.instructions).font(.darb(.subheadline, .heavy)).lineLimit(2)
                            Spacer(minLength: 0)
                            Text(Geo.distance(stepDistance(step) / 1000)).font(.darb(.caption, .bold)).opacity(0.7)
                        }
                        .padding(12)
                        .foregroundStyle(Color(hex: 0xFBF7EC))
                        .sticker(Color.onColor, radius: 18, line: 2, drop: 3)
                        .padding(.horizontal, 18).padding(.top, 12)
                        .transition(.opacity)
                    }

                    miniMap
                        .frame(height: min(210, geo.size.height * 0.24))
                        .sticker(Color.card, radius: 24)
                        .padding(.horizontal, 16).padding(.top, 14)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 10)
                }
            }
            .ignoresSafeArea()
        }
        .task {
            compass.start()
            await findRoute()
        }
        // the first real position is better than the one Darb measured from: the route is drawn again from it
        .onChange(of: compass.here == nil) { _, none in if !none, !routedFromLive { routedFromLive = true; Task { await findRoute() } } }
        .onChange(of: arrived) { _, now in if now { arrivedHops += 1; Haptic.done() } }
        .onDisappear { compass.stop() }
        // zoomed in at street level from the start, and kept there as the person walks and turns
        .onAppear { zoom(animated: false) }
        .onChange(of: compass.here) { zoom(animated: true) }
        .onChange(of: Int((compass.heading ?? 0) / 8)) { zoom(animated: true) }
    }

    // MARK: the compass ring

    private func ring(turn: Double, arrived: Bool, size: CGFloat) -> some View {
        let art = store.art(for: entry.business).render ?? Need.forKind(entry.business.kind)?.art ?? "p-plate"
        let ring = night ? Color(hex: 0xFBF7EC) : Color.onColor
        let size = size * 0.9
        return ZStack {
            Circle().strokeBorder(ring.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [3, 9]))
            Circle().fill(ring.opacity(0.06)).padding(size * 0.12)
            // the big arrow, always pointing at the place
            ZStack {
                Circle().fill(Color.mustard)
                Image(systemName: arrived ? "checkmark" : "arrow.up").font(.symbol(size: size * 0.17)).fontWeight(.black).foregroundStyle(Color.onColor)
                    .rotationEffect(.degrees(arrived ? 0 : turn))
            }
            .frame(width: size * 0.38, height: size * 0.38)
            .overlay { Circle().strokeBorder(Color.onColor, lineWidth: 3) }
            .background { Circle().fill(Color.onColor).offset(y: 5) }
            // the place's object rides the ring towards where the place is
            ArtImage(name: art)
                .frame(width: size * 0.3, height: size * 0.3)
                .padding(6)
                .background { Circle().fill(Color(hex: 0xFBF7EC)) }
                .overlay { Circle().strokeBorder(Color.onColor, lineWidth: 2.5) }
                .background { Circle().fill(Color.onColor).offset(y: 4) }
                .keyframeAnimator(initialValue: CGFloat(0), trigger: arrivedHops) { v, y in v.offset(y: y) } keyframes: { _ in
                    SpringKeyframe(-30, duration: 0.2, spring: .snappy)
                    SpringKeyframe(0, duration: 0.45, spring: .bouncy)
                }
                // placed on the ring at the same angle the arrow points, measured clockwise from the top
                .offset(x: arrived ? 0 : CGFloat(sin(turn * .pi / 180)) * size * 0.5,
                        y: arrived ? 0 : -CGFloat(cos(turn * .pi / 180)) * size * 0.5)
        }
        .frame(width: size, height: size)
        .environment(\.layoutDirection, .leftToRight)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82), value: turn)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: arrived)
        .accessibilityElement()
        .accessibilityLabel(arrived ? L("הגעתם") : L("החץ מצביע אל המקום"))
    }

    // MARK: the small map

    private var miniMap: some View {
        Map(position: $mapCamera) {
            UserAnnotation()
            if let r = route {
                MapPolyline(r.polyline).stroke(Color.onColor, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                MapPolyline(r.polyline).stroke(Color.mustard, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
            Annotation(entry.business.name, coordinate: dest, anchor: .bottom) {
                Circle().fill(Color.mustard).frame(width: 18, height: 18)
                    .overlay { Circle().strokeBorder(Color.onColor, lineWidth: 3) }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton() }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func zoom(animated: Bool) {
        let cam = MapCamera(centerCoordinate: start, distance: 260, heading: compass.heading ?? 0, pitch: 40)
        if animated { withAnimation(.easeOut(duration: 0.4)) { mapCamera = .camera(cam) } } else { mapCamera = .camera(cam) }
    }

    // MARK: the route

    /// The next step of the route still ahead: the first whose end point is further than 15 metres away.
    private var nextStep: MKRoute.Step? {
        guard let r = route else { return nil }
        let steps = r.steps.filter { !$0.instructions.isEmpty }
        return steps.first { stepDistance($0) > 15 } ?? steps.last
    }

    private func stepDistance(_ s: MKRoute.Step) -> Double {
        let n = s.polyline.pointCount
        guard n > 0 else { return 0 }
        let end = s.polyline.points()[n - 1].coordinate
        return CLLocation(latitude: start.latitude, longitude: start.longitude).distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
    }

    private func findRoute() async {
        let req = MKDirections.Request()
        req.source = Self.item(start)
        req.destination = Self.item(dest)
        req.transportType = .walking
        guard let r = try? await MKDirections(request: req).calculate().routes.first else { return }
        let from = start
        routeStraight = CLLocation(latitude: from.latitude, longitude: from.longitude).distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
        withAnimation(.smooth(duration: 0.4)) { route = r }
    }

    private static func item(_ c: CLLocationCoordinate2D) -> MKMapItem {
        if #available(iOS 26.0, *) {
            MKMapItem(location: CLLocation(latitude: c.latitude, longitude: c.longitude), address: nil)
        } else {
            MKMapItem(placemark: MKPlacemark(coordinate: c))
        }
    }

    /// Metres under a kilometre, else kilometres with one decimal, for the sign.
    static func short(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1f", m / 1000) : "\(Int((m / 10).rounded()) * 10)"
    }

    /// The compass bearing from one point to another, in degrees from north.
    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180, dl = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dl) * cos(p2), x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return atan2(y, x) * 180 / .pi
    }
}

/// The valley behind the walk: the sky at this hour, a low sun or moon, and three flat hills of Galilee houses.
private struct WalkValley: View {
    let night: Bool
    var body: some View {
        Canvas { g, size in
            let W = size.width, H = size.height
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(night ? Color(hex: 0x051811) : Color(hex: 0xFBF7EC)))
            let base = H * 0.62
            g.fill(Path(ellipseIn: CGRect(x: W * 0.82 - 22, y: base - H * 0.07 - 30, width: 44, height: 44)), with: .color(night ? Color(hex: 0xFBF7EC) : Color.mustard))
            let hills: [UInt32] = night ? [0x1F5240, 0x174435, 0x10372A] : [0xB5D19C, 0x93BC78, 0x6FA257]
            for (i, hex) in hills.enumerated() {
                let top = base - H * 0.07 + CGFloat(i) * H * 0.06
                var p = Path()
                p.move(to: CGPoint(x: 0, y: H))
                var x: CGFloat = 0
                while x <= W + 8 {
                    p.addLine(to: CGPoint(x: x, y: top + sin(x / W * .pi * (1.4 + Double(i) * 0.5) + Double(i)) * 14))
                    x += 8
                }
                p.addLine(to: CGPoint(x: W, y: H))
                p.closeSubpath()
                g.fill(p, with: .color(Color(hex: hex)))
                // a few flat roofed houses along the ridge, their windows lit by night
                var hx = W * (0.08 + Double(i) * 0.07)
                while hx < W - 20 {
                    let hy = top + sin(hx / W * .pi * (1.4 + Double(i) * 0.5) + Double(i)) * 14
                    let s = CGFloat(8 + i * 3)
                    let r = CGRect(x: hx, y: hy - s * 0.85, width: s, height: s * 0.9)
                    g.fill(Path(r), with: .color(night ? Color(hex: 0x03110C) : Color(hex: 0xF3EBDA)))
                    g.fill(Path(CGRect(x: r.minX + s * 0.15, y: r.minY - s * 0.2, width: s * 0.28, height: s * 0.2)), with: .color(Color(hex: 0x1C1F1A)))
                    if night || i == 2 { g.fill(Path(CGRect(x: r.minX + s * 0.3, y: r.minY + s * 0.3, width: s * 0.3, height: s * 0.3)), with: .color(Color.mustard)) }
                    hx += W * CGFloat(0.13 + Double(i) * 0.05)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The phone's facing and its fine position, only while the walking screen is open.
@MainActor @Observable
final class Compass: NSObject, CLLocationManagerDelegate {
    private(set) var heading: Double?
    private(set) var here: CLLocation?
    @ObservationIgnored private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        manager.headingFilter = 2
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.activityType = .fitness
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading h: CLHeading) {
        let v = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        Task { @MainActor in self.heading = v }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last, last.horizontalAccuracy >= 0, last.horizontalAccuracy < 100 else { return }
        Task { @MainActor in self.here = last }
    }
}
