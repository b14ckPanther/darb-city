import SwiftUI

/// The valley around the person at this hour, as if facing north: east is on the right, west on the left,
/// and nearer places sit lower, on the nearer hills.
///
/// Day and night are one drawing at two hours. The valley is drawn as its towns: a few houses for each, in the
/// town's real direction and distance, and as many of them marked open as the share of the town that is open now.
/// By day an open house has a coloured roof; by night it has a lit window. The largest towns carry their name and
/// the number open in them, with the same green dot that means "open" everywhere else in the app.
/// The hills start under the header, so its text always stands on clean sky.
///
/// How it is drawn. The picture is drawn once and kept: it is drawn again only when something it shows changes
/// (the place, the ten minutes, the language, the look). Nothing in it moves. Waking is the finished picture opening
/// outwards from where the person stands, over the sleeping one. The only thing that keeps moving is the small path
/// to the lead card's answer, which is a layer of its own and costs next to nothing.
struct ValleyView: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the valley starts waking up; nil keeps it asleep (behind the splash).
    let igniteAt: Date?
    /// The place the lead card answers with: it gets a ring, and a path runs to it from where the person is.
    var focus: Int? = nil
    /// How far down the header's own text reaches; the hills begin under it.
    var header: CGFloat = 0
    /// The valley has woken: the open places and the names are showing.
    @State private var awake = false

    static let igniteDuration = 1.1

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if size.width > 0, size.height > 0 {
                let key = ValleyKey(size: size, focus: focus, origin: store.origin, minute: store.minuteOfDay / 10, day: store.looksDay,
                                    low: store.looksDay && (store.hour < 8 || store.hour >= 17), lang: store.lang, open: store.openCount, header: header)
                let layout = ValleyLayout(store: store, key: key)
                let reach = hypot(size.width, size.height) * 2.1
                ZStack {
                    ValleyPicture(layout: layout, awake: false).equatable()
                    // when places open or close the new picture fades in over the old one, so windows go on
                    // and off softly instead of all at once
                    ValleyPicture(layout: layout, awake: true).equatable()
                        .id(key.open)
                        .transition(.opacity.animation(.easeInOut(duration: 0.9)))
                        // the finished picture opens outwards from where the person stands
                        .mask {
                            Circle().frame(width: reach, height: reach)
                                .scaleEffect(awake ? 1 : 0.001)
                                .position(layout.home)
                        }
                    if layout.focus != nil {
                        ValleyWay(layout: layout, still: reduceMotion)
                            .opacity(awake ? 1 : 0)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .onChange(of: igniteAt, initial: true) { _, at in
            guard at != nil, !awake else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: Self.igniteDuration)) { awake = true }
        }
        .accessibilityElement()
        .accessibilityLabel(L("%lld מקומות פתוחים סביב %@", store.openCount, store.homeName))
    }
}

/// Everything the picture depends on. Two valleys with the same key are the same picture.
struct ValleyKey: Equatable {
    let size: CGSize
    let focus: Int?
    let origin: Coordinate
    let minute: Int
    let day: Bool
    let low: Bool
    let lang: Lang
    let open: Int
    let header: CGFloat
}

/// The valley as a still picture. It is drawn again only when its key changes.
private struct ValleyPicture: View, Equatable {
    let layout: ValleyLayout
    let awake: Bool
    nonisolated static func == (a: ValleyPicture, b: ValleyPicture) -> Bool { a.awake == b.awake && a.layout.key == b.layout.key }
    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { g, _ in
            Perf.time("valley.draw") { layout.draw(in: &g, awake: awake) }
        }
    }
}

/// The path from where the person is to the lead card's answer, with its slow pulse.
private struct ValleyWay: View {
    let layout: ValleyLayout
    let still: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: still)) { ctx in
            Canvas(rendersAsynchronously: true) { g, _ in
                layout.drawWay(in: &g, t: still ? 0 : ctx.date.timeIntervalSinceReferenceDate)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ValleyLayout {
    struct House { let rect: CGRect; let open: Bool; let order: Int }
    struct Village { let houses: [House]; let layer: Int; let tree: CGPoint?; let ground: CGRect; let share: Double }
    struct Label { let text: String; let p: CGPoint; let open: Int }

    let key: ValleyKey
    let size: CGSize
    /// Drawn as day.
    let day: Bool
    /// The low light of the first and the last hour of the day.
    let low: Bool
    let villages: [Village]
    /// How many houses wake up one after another: roofs by day, windows by night.
    let wakeTotal: Int
    let stars: [(CGPoint, CGFloat, Double)]
    let labels: [Label]
    let focus: CGPoint?
    /// Where the person stands in the picture.
    let home: CGPoint
    let sun: CGPoint
    let rtl: Bool
    /// How far down the header's text reaches.
    let header: CGFloat
    /// Where the hills begin, and how the four ridges are spread under that line.
    let ridges: Ridges

    static let maxVillages = 22
    /// No town carries a label: the lights say how open each one is, and the screen keeps one thing to read.
    static let maxLabels = 0

    /// The four ridges, far to near. They fill the band under the header, however tall the header is.
    struct Ridges {
        let top: CGFloat
        let height: CGFloat
        private static let steps: [CGFloat] = [0, 0.19, 0.38, 0.58]
        private static let amp: [CGFloat] = [16, 12, 10, 7]
        private static let wav: [[CGFloat]] = [[0.011, 0.027, 0.052], [0.014, 0.031, 0.06], [0.017, 0.036, 0.07], [0.02, 0.045, 0.08]]
        private static let ph: [[CGFloat]] = [[0, 1.4, 2.2], [2.1, 0.3, 1.7], [1.1, 2.6, 0.4], [0.6, 1.9, 2.9]]

        /// - Parameters:
        ///   - header: how far down the header's text reaches; the far ridge never rises into it.
        init(height: CGFloat, header: CGFloat) {
            self.height = height
            let scale = Self.scale(height - max(height * 0.58, header + 28))
            top = max(height * 0.58, header + 12 + Self.amp[0] * scale)
        }
        private static func scale(_ band: CGFloat) -> CGFloat { min(1, max(0.5, band / 126)) }
        private var band: CGFloat { height - top }
        func base(_ i: Int) -> CGFloat { top + band * Self.steps[i] }
        func at(_ i: Int, _ x: CGFloat) -> CGFloat {
            let w = Self.wav[i], p = Self.ph[i]
            return base(i) - Self.amp[i] * Self.scale(band) * (sin(x * w[0] + p[0]) * 0.6 + sin(x * w[1] + p[1]) * 0.3 + sin(x * w[2] + p[2]) * 0.1)
        }
    }

    /// Which hill a distance falls on: the nearest places on the nearest hill.
    static func layer(km: Double) -> Int { km < 4 ? 3 : (km < 10 ? 2 : (km < 18 ? 1 : 0)) }

    /// For a test: the valley as the store has it now.
    @MainActor
    init(store: Store, size: CGSize, focus: Int?, header: CGFloat = 0) {
        self.init(store: store, key: ValleyKey(size: size, focus: focus, origin: store.origin, minute: store.minuteOfDay / 10, day: store.looksDay,
                                               low: store.looksDay && (store.hour < 8 || store.hour >= 17), lang: store.lang, open: store.openCount, header: header))
    }

    /// The towns come from the store already counted, so laying the valley out is a matter of a few hundred towns,
    /// not of every place in them.
    @MainActor
    init(store: Store, key: ValleyKey) {
        self.key = key
        let size = key.size, header = key.header
        self.size = size
        self.header = header
        day = key.day
        low = key.low
        rtl = key.lang.isRTL
        let W = size.width, H = size.height
        let ridges = Ridges(height: H, header: header)
        self.ridges = ridges
        home = CGPoint(x: W / 2, y: H - 42)
        let bottomLimit = H - 50
        let bands: [(Double, Double)] = [(18, 30), (10, 18), (4, 10), (0, 4)]

        /// Where a place stands in the picture, from its bearing and its distance.
        func spot(bearing: Double, km: Double) -> (CGPoint, Int) {
            let layer = Self.layer(km: km)
            let x = min(W - 6, max(6, W / 2 + CGFloat(bearing / Double.pi) * (W / 2 - 8)))
            let top = ridges.at(layer, x) + 4
            let bottom = layer == 3 ? bottomLimit : min(ridges.at(layer + 1, x) + 1, bottomLimit)
            let (lo, hi) = bands[layer]
            let f = CGFloat(min(1, max(0, (km - lo) / (hi - lo))))
            return (CGPoint(x: x, y: bottom - f * max(2, bottom - top)), layer)
        }

        var focusPoint: CGPoint?
        if let id = key.focus, let b = store.business(id), b.km < store.maxKm {
            focusPoint = spot(bearing: store.bearing(to: b), km: b.km).0
        }

        // towns: how many places each has near here, how many are open, and where it stands
        let towns = store.townStats.map { t in (slug: t.slug, n: t.n, open: t.open, x: min(W - 6, max(6, W / 2 + CGFloat(t.dir / Double(t.n)) * (W / 2 - 8))), km: t.km / Double(t.n)) }

        // The towns as villages, the largest first. Nothing is drawn on top of anything else: a village keeps clear
        // of the others, of the names, of where the person stands and of the place the path leads to.
        var built: [Village] = []
        var named: [Label] = []
        var taken: [CGRect] = [CGRect(x: W / 2 - 16, y: H - 58, width: 32, height: 30)]
        if let f = focusPoint { taken.append(CGRect(x: f.x - 13, y: f.y - 13, width: 26, height: 26)) }
        var roofOrder = 0
        var vrng = SeededRandom(seed: 29)
        let floor = header + 12
        for t in towns where built.count < Self.maxVillages && t.n >= 3 {
            let slug = t.slug, km = t.km
            let layer = Self.layer(km: km)
            let unit: CGFloat = [3.6, 4.6, 5.8, 7.2][layer]
            let count = min([4, 6, 8, 10][layer], 2 + Int(log2(Double(t.n) + 1)))
            let spread = CGFloat(count) * unit * 0.62
            let cx = min(W - spread - unit - 8, max(spread + unit + 8, t.x))
            // the sheet of needs covers the foot of the valley, and no village is drawn under it
            let limit = H - 44 - unit * 1.3
            let top = min(limit, ridges.at(layer, cx) + unit * 1.7)
            let bottom = max(top, min(limit, layer == 3 ? bottomLimit - 16 : ridges.at(layer + 1, cx) - unit * 0.3))
            let (lo, hi) = bands[layer]
            let f = CGFloat(min(1, max(0, (km - lo) / (hi - lo))))
            let cy = bottom - f * (bottom - top)
            let ground = CGRect(x: cx - spread - unit, y: cy - unit * 1.9, width: (spread + unit) * 2, height: unit * 3.2)
            if taken.contains(where: { $0.insetBy(dx: -5, dy: -2).intersects(ground) }) { continue }

            // a name stands right above its own village, and only where it is clear of everything
            if named.count < Self.maxLabels {
                let name = store.placeName(slug)
                let w = CGFloat(name.count) * 6.8 + 50, hgt: CGFloat = 22
                let x = min(W - w / 2 - 8, max(w / 2 + 8, cx))
                let frame = CGRect(x: x - w / 2, y: max(floor, ground.minY - hgt - 2), width: w, height: hgt)
                // if the name has no room above, the village moves down to make room, when there is any
                let pushed = ground.offsetBy(dx: 0, dy: max(0, frame.maxY + 2 - ground.minY))
                if pushed.maxY <= H - 44, !taken.contains(where: { $0.insetBy(dx: -6, dy: -3).intersects(frame) || $0.insetBy(dx: -5, dy: -2).intersects(pushed) }) {
                    taken.append(frame)
                    named.append(Label(text: name, p: CGPoint(x: frame.midX, y: frame.midY), open: t.open))
                    built.append(Self.village(count: count, unit: unit, centre: CGPoint(x: cx, y: cy + pushed.minY - ground.minY), ground: pushed, layer: layer, open: t.open, of: t.n, order: &roofOrder, rng: &vrng))
                    taken.append(pushed)
                    continue
                }
            }
            taken.append(ground)
            built.append(Self.village(count: count, unit: unit, centre: CGPoint(x: cx, y: cy), ground: ground, layer: layer, open: t.open, of: t.n, order: &roofOrder, rng: &vrng))
        }
        villages = built
        labels = named
        wakeTotal = roofOrder
        focus = focusPoint

        // a few stars, in the sky only
        var srng = SeededRandom(seed: 3)
        stars = (0..<46).map { _ in (CGPoint(x: CGFloat(srng.next()) * W, y: CGFloat(srng.next()) * (ridges.top - 14)), CGFloat(srng.next() * 0.7 + 0.3), srng.next()) }

        // the sun crosses from the east (right) to the west (left) through the day
        let turn = CGFloat(min(1, max(0, Double(key.minute * 10 - 360) / 720)))
        sun = CGPoint(x: W * (0.84 - 0.68 * turn), y: H * (0.42 - 0.18 * sin(.pi * turn)))
    }

    /// One town's houses. As many of them are open as the share of the town that is open now, and at least one if any is.
    private static func village(count: Int, unit: CGFloat, centre: CGPoint, ground: CGRect, layer: Int, open: Int, of total: Int, order: inout Int, rng: inout SeededRandom) -> Village {
        let spread = CGFloat(count) * unit * 0.62
        let lit = open == 0 ? 0 : min(count, max(1, Int((Double(count) * Double(open) / Double(max(1, total))).rounded())))
        // which houses are the open ones is settled by the draw, so they are spread through the village
        var slots = Array(0..<count)
        for i in slots.indices.reversed() where i > 0 { slots.swapAt(i, Int(rng.next() * Double(i + 1))) }
        let openSet = Set(slots.prefix(lit))
        var houses: [House] = []
        for i in 0..<count {
            let w = unit * CGFloat(0.95 + rng.next() * 0.45), hgt = unit * CGFloat(0.85 + rng.next() * 0.5)
            let x = centre.x - spread + (CGFloat(i) + 0.5) * (spread * 2 / CGFloat(count)) + CGFloat(rng.next() - 0.5) * unit * 0.4
            let y = centre.y + CGFloat(rng.next() - 0.5) * unit * 1.4
            let isOpen = openSet.contains(i)
            houses.append(House(rect: CGRect(x: x - w / 2, y: y - hgt, width: w, height: hgt), open: isOpen, order: isOpen ? order : 0))
            if isOpen { order += 1 }
        }
        houses.sort { $0.rect.maxY < $1.rect.maxY }
        let tree: CGPoint? = count >= 5 ? CGPoint(x: centre.x + (rng.next() < 0.5 ? -1 : 1) * (spread + unit * 0.8), y: centre.y + unit * 0.3) : nil
        return Village(houses: houses, layer: layer, tree: tree, ground: ground, share: Double(open) / Double(max(1, total)))
    }

    private func hillPath(_ i: Int) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: ridges.at(i, 0)))
        var x: CGFloat = 4
        while x <= size.width + 4 { p.addLine(to: CGPoint(x: x, y: ridges.at(i, x))); x += 4 }
        p.addLine(to: CGPoint(x: size.width + 4, y: size.height + 4))
        p.addLine(to: CGPoint(x: 0, y: size.height + 4))
        p.closeSubpath()
        return p
    }

    /// A house as the Galilee builds them: a flat roofed cube with a low parapet, a black water tank on the roof
    /// and, on most, the tilted panel of a solar heater beside it.
    private func galileeHouse(_ g: inout GraphicsContext, _ r: CGRect, wall: Color, shade: Color, roof: Color, tank: Color, seed: Int) {
        g.fill(Path(r), with: .color(wall))
        // the side in shade, a third of the face
        g.fill(Path(CGRect(x: r.minX + r.width * 0.66, y: r.minY, width: r.width * 0.34, height: r.height)), with: .color(shade))
        // the parapet: a thin band a touch wider than the walls
        g.fill(Path(CGRect(x: r.minX - r.width * 0.04, y: r.minY - r.height * 0.07, width: r.width * 1.08, height: r.height * 0.12)), with: .color(roof))
        let u = r.width
        // the water tank, a short black drum
        let tankW = u * 0.26, tankH = u * 0.2
        let tx = seed % 2 == 0 ? r.minX + u * 0.14 : r.maxX - u * 0.14 - tankW
        g.fill(Path(roundedRect: CGRect(x: tx, y: r.minY - r.height * 0.07 - tankH, width: tankW, height: tankH), cornerRadius: tankW * 0.18), with: .color(tank))
        // the solar heater's panel, leaning
        if seed % 3 != 0 {
            var panel = Path()
            let px = seed % 2 == 0 ? r.maxX - u * 0.42 : r.minX + u * 0.12
            let base = r.minY - r.height * 0.07
            panel.move(to: CGPoint(x: px, y: base))
            panel.addLine(to: CGPoint(x: px + u * 0.3, y: base))
            panel.addLine(to: CGPoint(x: px + u * 0.22, y: base - u * 0.16))
            panel.addLine(to: CGPoint(x: px - u * 0.04, y: base - u * 0.16))
            panel.closeSubpath()
            g.fill(panel, with: .color(tank.opacity(0.75)))
        }
    }

    /// An olive tree: a low, wide, grey green crown on a short dark trunk.
    private func olive(_ g: inout GraphicsContext, at p: CGPoint, size s: CGFloat, crown: Color, trunk: Color) {
        g.fill(Path(CGRect(x: p.x - s * 0.06, y: p.y - s * 0.45, width: s * 0.12, height: s * 0.45)), with: .color(trunk))
        g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.55, y: p.y - s * 1.05, width: s * 1.1, height: s * 0.7)), with: .color(crown))
        g.fill(Path(ellipseIn: CGRect(x: p.x - s * 0.2, y: p.y - s * 1.25, width: s * 0.7, height: s * 0.55)), with: .color(crown))
    }

    private func disc(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }

    /// The whole picture. Asleep, no place is marked open and no town is named; awake, they all are.
    func draw(in g: inout GraphicsContext, awake: Bool) {
        if day { drawDay(in: &g, awake: awake) } else { drawNight(in: &g, awake: awake) }
        // where the person is
        g.fill(disc(home, 10), with: .color(day ? .white.opacity(0.6) : Color(hex: 0xFFC330, opacity: 0.25)))
        g.fill(disc(home, 6), with: .color(day ? .white : Color(hex: 0x0A2A1F)))
        g.fill(disc(home, 3.8), with: .color(day ? Color(hex: 0x0B2219) : Color(hex: 0xFFC330)))
    }

    /// How strongly each hill is drawn: the far ones softer, through the air between.
    private static let near: [Double] = [0.55, 0.7, 0.86, 1]

    // MARK: night

    private func drawNight(in g: inout GraphicsContext, awake: Bool) {
        let W = size.width
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x051811)))
        for (p, r, bright) in stars { g.fill(disc(p, r), with: .color(.white.opacity(0.16 + 0.36 * bright))) }
        // the moon sits low on the far ridge, half behind it
        g.fill(disc(CGPoint(x: W * 0.5, y: ridges.top + 4), 16), with: .color(Color(hex: 0xFBF7EC)))

        // far hills are lighter and bluer, the near one is the darkest: the same air as by day
        let hill: [UInt32] = [0x1F5240, 0x174435, 0x10372A, 0x0A2A1F]
        for layer in 0..<4 {
            let body = Color(hex: hill[layer])
            g.fill(hillPath(layer), with: .color(body))
            let a = Self.near[layer]
            let mine = villages.filter { $0.layer == layer }
            for v in mine {
                if let tr = v.tree {
                    olive(&g, at: tr, size: v.ground.height * 0.42, crown: Color(hex: 0x03110C).opacity(0.5 + 0.4 * a), trunk: Color(hex: 0x03110C))
                }
                for (i, h) in v.houses.enumerated() {
                    // a house is a quiet silhouette against its hill; the parapet catches a little moonlight
                    let wall = body.mix(with: Color(hex: 0x03110C), by: 0.42)
                    galileeHouse(&g, h.rect, wall: wall, shade: wall.mix(with: Color(hex: 0x03110C), by: 0.25),
                                 roof: body.mix(with: Color(hex: 0xFBF7EC), by: 0.12 + 0.08 * a), tank: Color(hex: 0x020806), seed: i + Int(h.rect.minX))
                }
            }
            // an open place: its window is lit, a flat mustard light
            for v in mine {
                for h in v.houses {
                    guard awake, h.open else { continue }
                    let o = 1.0
                    let r = h.rect
                    let win = CGRect(x: r.midX - r.width * 0.3, y: r.minY + r.height * 0.34, width: r.width * 0.6, height: r.height * 0.5)
                    g.fill(Path(roundedRect: win, cornerRadius: win.width * 0.2), with: .color(Color(hex: 0xFFC330).opacity(o * (0.75 + 0.25 * a))))
                }
            }
        }
    }

    // MARK: day

    private func drawDay(in g: inout GraphicsContext, awake: Bool) {
        // the sky is Darb's ivory, warmer in the low sun: the valley reads as a print, not a photograph
        let sky: [UInt32] = low ? [0xF6E7C9] : [0xFBF7EC]
        // far hills are paler and bluer, the way distance looks through morning air
        let hill: [UInt32] = low ? [0xB7C29A, 0x97AE79, 0x75965A, 0x557D42] : [0xB5D19C, 0x93BC78, 0x6FA257, 0x4E873D]
        g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: sky[0])))
        // the sun sits low on the far ridge, half behind it, well clear of the words above
        g.fill(disc(CGPoint(x: size.width * 0.5, y: ridges.top + 6), 22), with: .color(Color(hex: 0xFFC330)))

        for layer in 0..<4 {
            let body = Color(hex: hill[layer])
            g.fill(hillPath(layer), with: .color(body))
            let a = Self.near[layer]
            for v in villages where v.layer == layer {
                if let tr = v.tree {
                    olive(&g, at: tr, size: v.ground.height * 0.42, crown: Color(hex: 0x7C8F5E).mix(with: body, by: 1 - a), trunk: Color(hex: 0x4A3F2E).mix(with: body, by: 1 - a))
                }
                for (i, h) in v.houses.enumerated() {
                    let r = h.rect, far = (1 - a) * 0.8
                    galileeHouse(&g, r, wall: Color(hex: 0xF3EBDA).mix(with: body, by: far), shade: Color(hex: 0xDCCFB7).mix(with: body, by: far),
                                 roof: Color(hex: 0xC9BBA0).mix(with: body, by: far), tank: Color(hex: 0x1C1F1A).mix(with: body, by: far * 0.6), seed: i + Int(r.minX))
                    // an open place: its window is a mustard light, the same sign as by night
                    if awake, h.open {
                        let win = CGRect(x: r.minX + r.width * 0.18, y: r.minY + r.height * 0.36, width: r.width * 0.36, height: r.height * 0.4)
                        g.fill(Path(win), with: .color(Color(hex: 0xE0A21C).mix(with: body, by: far * 0.5)))
                    }
                }
            }
        }
    }

    // MARK: the way

    /// The path from where the person is to the place the lead card answers with. This is the one part that moves.
    func drawWay(in g: inout GraphicsContext, t: Double) {
        guard let f = focus else { return }
        let tone = day ? Color.onColor : Color.lamp
        var road = Path()
        road.move(to: home)
        road.addQuadCurve(to: f, control: CGPoint(x: (home.x + f.x) / 2 + (f.y - home.y) * 0.25, y: max(ridges.top, min(home.y, f.y) - abs(f.x - home.x) * 0.2 - 10)))
        g.stroke(road, with: .color(tone.opacity(0.9)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [1, 5], dashPhase: -CGFloat((t * 7).truncatingRemainder(dividingBy: 6))))
        let beat = (t / 2.2).truncatingRemainder(dividingBy: 1)
        let rr = 5 + 9 * beat
        g.stroke(disc(f, rr), with: .color(tone.opacity((1 - beat) * 0.8)), lineWidth: 1.4)
        g.fill(disc(f, 5), with: .color(tone))
        g.fill(disc(f, 2.2), with: .color(day ? Color.white : Color(hex: 0x0A2A1F)))
    }
}

/// A small deterministic generator, so the valley looks the same on every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state >> 11) / Double(1 << 53)
    }
}
