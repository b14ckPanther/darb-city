import SwiftUI

/// A Deluxe client's shop, drawn by Darb from the client's own system. You step through Darb's doorway into the
/// business's own world: their colours, their photos or their products in the window, their menu or shelf by
/// category, and a bag that fills as you pick. The order goes to the business on WhatsApp, written out.
/// Darb's own words here follow the shop's language, so a screen never mixes two.
struct ShopView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let business: Business
    let source: ShopSource

    @State private var shop: Shop?
    @State private var failed = false
    @State private var opened = false
    @State private var category: String?
    @State private var focus: Shop.Item?
    @Namespace private var dishNS
    @State private var bag: [BagLine] = []
    @State private var bagOpen = false
    @State private var drop: (item: Shop.Item, id: UUID)?
    @State private var pull: CGFloat = 0
    @State private var page: String?
    /// The language the shop is read in; it starts as the app's and can be changed here alone.
    @State private var lang: ShopLang?
    private var shopLang: ShopLang { source.lang(lang ?? ShopLang(store.lang)) }
    private var ui: Lang { shopLang.ui }

    private var bg: Color { Color(hex: source.bg) }
    private var surface: Color { Color(hex: source.surface) }
    private var ink: Color { Color(hex: source.ink) }
    private var accent: Color { Color(hex: source.accent) }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            if let shop {
                content(shop)
                    .opacity(opened ? 1 : 0)
                    .offset(y: opened ? 0 : 30)
            } else if failed {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.symbol(size: 30))
                    Text(L("לא הצלחנו לפתוח את החנות עכשיו", in: ui)).font(.darb(.headline, .bold))
                    Button(L("לנסות שוב", in: ui)) { Task { await load() } }.font(.darb(.body, .heavy)).tint(accent)
                }
                .foregroundStyle(ink)
            }
            doorway
        }
        .offset(y: max(0, pull))
        .gesture(DragGesture(minimumDistance: 20).onChanged { g in if g.startLocation.y < 140 { pull = g.translation.height } }
            .onEnded { g in if pull > 140 { dismiss() } else { withAnimation(.spring(response: 0.3)) { pull = 0 } } })
        .environment(\.colorScheme, source.light ? .light : .dark)
        .environment(\.layoutDirection, shopLang.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, shopLang.locale)
        // the status bar reads on the shop's own colour
        .preferredColorScheme(source.light ? .light : .dark)
        .task { await open() }
        .overlay {
            if let item = focus {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.45).ignoresSafeArea()
                        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { focus = nil } }
                    ItemSheet(item: item, ink: ink, bg: surface, accent: accent, ui: ui, ns: dishNS, system: source.system,
                              close: { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { focus = nil } }) { size in
                        if source.orders { add(item, size: size) } else { ask(item) }
                    }
                        .padding(.horizontal, 12).padding(.bottom, 10)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
                .zIndex(3)
            }
        }
        .sheet(isPresented: $bagOpen) {
            BagSheet(lines: $bag, ink: ink, bg: surface, accent: accent, ui: ui, name: shop?.name ?? business.name,
                     minOrder: shop?.minOrder, note: shop?.note) { send() }
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(34)
                .presentationBackground(surface)
                .environment(\.colorScheme, source.light ? .light : .dark)
                .environment(\.layoutDirection, shopLang.isRTL ? .rightToLeft : .leftToRight)
        }
    }

    // MARK: the doorway

    /// Darb's doorway, glowing in the business's colour, grows until it fills the screen and the shop is behind it.
    private var doorway: some View {
        GeometryReader { geo in
            let full = max(geo.size.width, geo.size.height) * 2.6
            ZStack {
                Color(hex: 0x0B2219).opacity(opened ? 0 : 1)
                RoundedRectangle(cornerRadius: opened ? full / 2 : 40, style: .continuous)
                    .fill(accent)
                    .frame(width: opened ? full : 92, height: opened ? full : 140)
                    .opacity(opened ? 0 : 1)
                Image("Mark").resizable().scaledToFit().frame(width: 70, height: 70)
                    .offset(y: -110)
                    .opacity(opened ? 0 : 1)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func open() async {
        shop = ShopLoader.cached(business.id, lang: shopLang)
        category = shop?.categories.first?.id
        page = shop?.featured.first
        try? await Task.sleep(for: .seconds(0.25))
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeIn(duration: 0.55)) { opened = true }
        await load()
    }

    /// Reads the shop again in another language, showing the last copy in it at once when there is one.
    private func switchTo(_ l: ShopLang) {
        lang = l
        if let c = ShopLoader.cached(business.id, lang: l) { self.shop = c }
        Task { await load() }
    }

    private func load() async {
        do {
            let fresh = try await ShopLoader.fetch(business.id, lang: shopLang)
            withAnimation(.smooth) {
                shop = fresh; failed = false
                if category == nil || !fresh.categories.contains(where: { $0.id == category }) { category = fresh.categories.first?.id }
                if page == nil { page = fresh.featured.first }
            }
            Task(priority: .utility) { await ShopLoader.warm(fresh, ready: true) }
        } catch {
            if shop == nil { failed = true }
        }
    }

    // MARK: the shop

    private func content(_ shop: Shop) -> some View {
        VStack(spacing: 0) {
            topBar(shop)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero(shop)
                    categories(shop)
                    counter(shop)
                    Color.clear.frame(height: 100)
                }
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) { bagBar }
    }

    /// The shop's own bar, under the status bar: the way out, and the shop's language when it keeps more than one.
    private func topBar(_ shop: Shop) -> some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.symbol(.body)).foregroundStyle(ink)
                    .frame(width: 40, height: 40).background(surface, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("יציאה מהחנות", in: ui))
            Spacer()
            if source.langs.count > 1 {
                Menu {
                    ForEach(source.langs) { l in
                        Button { switchTo(l) } label: {
                            if l == shopLang { Label(l.endonym, systemImage: "checkmark") } else { Text(l.endonym) }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe").font(.symbol(.subheadline))
                        Text(shopLang.endonym).font(.darb(.subheadline, .bold))
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(surface, in: Capsule())
                    .frame(height: 44)
                }
                .accessibilityLabel(L("web.messages.language", in: ui))
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 6)
        .background(bg)
    }

    /// The window, and under it their logo, ringed, with their name and line. The window is their own photos, or,
    /// for a shop of products, the products they put in front, each standing on its own colour, turning by itself.
    private func hero(_ shop: Shop) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if !shop.heroes.isEmpty {
                    TabView {
                        ForEach(shop.heroes, id: \.self) { url in
                            KeptImage(url: url, fill: surface) { $0.resizable().scaledToFill() }
                                .clipped()
                        }
                    }
                    .frame(height: 210)
                } else {
                    let window = shop.windowItems
                    TabView(selection: $page) {
                        ForEach(window) { it in
                            Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { focus = it } } label: {
                                ZStack(alignment: .bottomLeading) {
                                    ItemArt(item: it, fill: surface, pad: 18)
                                    Text(it.name).font(.darb(.subheadline, .heavy)).foregroundStyle(ink)
                                        .padding(.horizontal, 12).frame(height: 32)
                                        .background(surface, in: Capsule())
                                        .padding(12).padding(.bottom, 14)
                                }
                            }
                            .buttonStyle(.plain)
                            .tag(Optional(it.id))
                        }
                    }
                    .frame(height: 260)
                    .task(id: window.map(\.id)) {
                        guard window.count > 1, !reduceMotion else { return }
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(3.6))
                            guard focus == nil else { continue }
                            let i = window.firstIndex { $0.id == page } ?? 0
                            withAnimation(.smooth(duration: 0.6)) { page = window[(i + 1) % window.count].id }
                        }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(accent.opacity(0.4), lineWidth: 1) }
            HStack(alignment: .center, spacing: 14) {
                LogoRing(url: shop.logo, bg: bg, accent: accent, size: 84)
                    .offset(y: -30).padding(.bottom, -30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(shop.name).font(.darb(size: 26, .black, relativeTo: .title)).lineLimit(2).minimumScaleFactor(0.7)
                    if let t = shop.tagline { Text(t).font(.darb(.subheadline, .bold)).foregroundStyle(accent) }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 6).padding(.top, 12)
        }
        .padding(.horizontal, 16)
    }

    /// The categories as round buttons: a photo of the tray, or, for hair types, the strand itself, curled as much
    /// as that hair curls.
    private func categories(_ shop: Shop) -> some View {
        // up to six fit across the screen, drawn smaller the more there are
        let n = shop.categories.count
        let compact = n >= 5
        let circle: CGFloat = n >= 6 ? 52 : n == 5 ? 60 : 70
        let cell: CGFloat = n >= 6 ? 58 : n == 5 ? 68 : 82
        return ScrollView(.horizontal) {
            HStack(spacing: n >= 6 ? 2 : compact ? 6 : 14) {
                ForEach(shop.categories) { c in
                    let on = c.id == category
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { category = c.id }; Haptic.tap() } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let image = c.image {
                                    KeptImage(url: image, fill: surface) { $0.resizable().scaledToFill() }
                                } else if source.system == .lot {
                                    Image(systemName: Self.bodySymbol(c.id)).font(.symbol(size: circle * 0.36))
                                        .foregroundStyle(on ? accent : ink)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(surface)
                                } else {
                                    Strands(curls: c.curl.map { [$0, $0, $0] } ?? [0.08, 0.5, 0.95], ink: on ? accent : ink)
                                        .padding(circle * 0.22)
                                        .background(surface)
                                }
                            }
                            .frame(width: circle, height: circle).clipShape(Circle())
                            .overlay { Circle().strokeBorder(on ? accent : ink.opacity(0.15), lineWidth: on ? 3 : 1) }
                            .scaleEffect(on ? 1.08 : 1)
                            Text(c.name).font(.darb(.caption, on ? .heavy : .semibold)).lineLimit(1)
                                .foregroundStyle(on ? accent : ink.opacity(0.8))
                        }
                        .frame(width: cell)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, n >= 6 ? 10 : 16)
            .containerRelativeFrame(.horizontal, alignment: .center) { w, _ in w }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// The category's dishes or products, two by two.
    private func counter(_ shop: Shop) -> some View {
        // what can be had first; anything sold or sold out goes to the bottom, in its own order
        let all = shop.items.filter { category.map($0.categories.contains) ?? true }
        let items = all.filter(\.available) + all.filter { !$0.available }
        return VStack(alignment: .leading, spacing: 12) {
            if let c = shop.categories.first(where: { $0.id == category }) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.name).font(.darb(size: 26, .black, relativeTo: .title))
                    Text(verbatim: "\(items.count)").font(.darb(.subheadline, .bold)).foregroundStyle(accent)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 16)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(items) { it in
                    Button { withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { focus = it } } label: {
                        DishCard(item: it, ink: ink, surface: surface, accent: accent, ui: ui, ns: dishNS, system: source.system, hidden: focus?.id == it.id)
                    }
                    .buttonStyle(PressStyle(scale: 0.96))
                }
            }
            .padding(.horizontal, 16)
            .id(category)
            .transition(.opacity)
        }
    }

    // MARK: the bag

    /// The bag. Empty, there is nothing at the bottom: the window has the whole screen. The first pick raises it
    /// from below: the picks so far, fanned like photos in a hand, how many, and the total on a lit tag.
    private var bagBar: some View {
        let count = bag.reduce(0) { $0 + $1.qty }
        let total = bag.reduce(0) { $0 + $1.price * Double($1.qty) }
        let fan = Array(bag.suffix(3).reversed())
        return ZStack {
            if count > 0 {
                Button { bagOpen = true } label: {
                    HStack(spacing: 14) {
                        // the picks, fanned, the newest on top
                        ZStack {
                            ForEach(Array(fan.enumerated()), id: \.element.id) { k, l in
                                ItemArt(item: l.item, fill: surface, pad: 3)
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(bg, lineWidth: 2) }
                                    .rotationEffect(.degrees(Double(k) * -9 + 4))
                                    .offset(x: CGFloat(k) * -10)
                                    .zIndex(Double(3 - k))
                            }
                        }
                        .frame(width: 70, height: 52)
                        .environment(\.layoutDirection, .leftToRight)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("הסל שלי", in: ui)).font(.darb(.headline, .black))
                            Text(L("%lld פריטים", in: ui, count)).font(.darb(.caption, .bold)).opacity(0.7)
                                .contentTransition(.numericText(value: Double(count)))
                        }
                        Spacer(minLength: 6)
                        HStack(spacing: 6) {
                            Text(Self.money(total)).font(.darb(.title3, .black)).monospacedDigit()
                                .contentTransition(.numericText(value: total))
                            Image(systemName: "chevron.up").font(.symbol(.footnote))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 14).frame(height: 44)
                        .background(bg, in: Capsule())
                    }
                    .foregroundStyle(bg)
                    .padding(.leading, 10).padding(.trailing, 8).frame(height: 68)
                    .background(accent, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: count) { v, s in v.scaleEffect(s) } keyframes: { _ in
                        SpringKeyframe(1.04, duration: 0.12); SpringKeyframe(1, duration: 0.35, spring: .bouncy)
                    }
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: count > 0)
        .padding(.horizontal, 16).padding(.bottom, 8)
        .overlay {
            // the pick drops into the bag
            if let d = drop {
                ItemArt(item: d.item, fill: surface, pad: 4)
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .keyframeAnimator(initialValue: DropFrame(), trigger: d.id) { v, f in
                        v.offset(x: f.x, y: f.y).scaleEffect(f.s).opacity(f.o)
                    } keyframes: { _ in
                        KeyframeTrack(\.y) { CubicKeyframe(-420, duration: 0.01); SpringKeyframe(-10, duration: 0.5, spring: .snappy) }
                        KeyframeTrack(\.s) { CubicKeyframe(1.4, duration: 0.01); CubicKeyframe(0.3, duration: 0.5) }
                        KeyframeTrack(\.o) { CubicKeyframe(1, duration: 0.45); CubicKeyframe(0, duration: 0.1) }
                    }
                    .id(d.id)
                    .allowsHitTesting(false)
            }
        }
    }

    private func add(_ item: Shop.Item, size: Int?) {
        guard let base = item.price else { return }
        let price = size.flatMap { item.sizes?[$0] } ?? base
        if let i = bag.firstIndex(where: { $0.item.id == item.id && $0.size == size }) { bag[i].qty += 1 }
        else { bag.append(BagLine(item: item, size: size, price: price, qty: 1)) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { focus = nil }
        Haptic.done()
        drop = (item, UUID())
    }

    /// A lot is asked about one car at a time: the question goes on WhatsApp in the lot's own words.
    private func ask(_ item: Shop.Item) {
        var c = URLComponents(string: "https://wa.me/" + Outside.waDigits(source.whatsapp))
        c?.queryItems = [URLQueryItem(name: "text", value: item.ask ?? item.name)]
        if let url = c?.url { Analytics.log(.order, business.id); Haptic.done(); openURL(url) }
    }

    private func send() {
        let lines = bag.map { l -> String in
            let size = l.size.map { [" S", " M", " L"][$0] } ?? ""
            return "\(l.qty) × \(l.item.name)\(size) · \(Self.money(l.price * Double(l.qty)))"
        }
        let total = bag.reduce(0) { $0 + $1.price * Double($1.qty) }
        let text = L("היי, הזמנה דרך דרב:", in: ui) + "\n" + lines.joined(separator: "\n") + "\n" + L("סה״כ %@", in: ui, Self.money(total))
        var c = URLComponents(string: "https://wa.me/" + Outside.waDigits(source.whatsapp))
        c?.queryItems = [URLQueryItem(name: "text", value: text)]
        if let url = c?.url { Analytics.log(.order, business.id); openURL(url) }
    }

    /// A car's body as a symbol, for the lot's categories.
    static func bodySymbol(_ id: String) -> String {
        switch id {
        case "*": "car.2.fill"
        case "suv", "crossover": "suv.side.fill"
        case "pickup": "truck.pickup.side.fill"
        case "van", "commercial", "mpv": "bus.fill"
        case "sold": "checkmark.seal.fill"
        case "convertible", "coupe": "car.rear.fill"
        default: "car.side.fill"
        }
    }

    static func money(_ v: Double) -> String { "₪" + (v.rounded() == v ? String(Int(v)) : String(format: "%.2f", v)) }
}

struct BagLine: Identifiable, Hashable {
    let item: Shop.Item
    let size: Int?
    let price: Double
    var qty: Int
    var id: String { "\(item.id)-\(size ?? -1)" }
}

private struct DropFrame { var x: CGFloat = 0; var y: CGFloat = 0; var s: CGFloat = 1; var o: Double = 1 }

/// An item's picture: a photo filling its frame, or a product photographed cut out, standing on its own colour.
struct ItemArt: View {
    let item: Shop.Item
    let fill: Color
    var pad: CGFloat = 10
    var body: some View {
        if let t = item.tint {
            Color(hex: t).overlay {
                KeptImage(url: item.image, fill: .clear) { $0.resizable().scaledToFit() }.padding(pad)
            }
        } else {
            fill.overlay { KeptImage(url: item.image, fill: fill) { $0.resizable().scaledToFill() } }.clipped()
        }
    }
}

/// Strands of hair, each curled as much as its number says: 0 lies straight, 1 coils tight.
struct Strands: View {
    let curls: [Double]
    let ink: Color
    var body: some View {
        Canvas { ctx, size in
            let n = curls.count
            for (k, curl) in curls.enumerated() {
                let x0 = size.width * (CGFloat(k) + 0.5) / CGFloat(n)
                let amp = (1.2 + curl * 4.5) * size.width / 42
                let turns = 0.6 + curl * 2.6
                var p = Path()
                let steps = 40
                for s in 0...steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let y = size.height * (0.04 + 0.92 * t)
                    let x = x0 + amp * sin(t * turns * 2 * .pi + CGFloat(k))
                    if s == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: size.width / 14, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A dish or product in the grid: its picture, and its name and price on a small card at its foot.
private struct DishCard: View {
    let item: Shop.Item
    let ink: Color, surface: Color, accent: Color
    let ui: Lang
    let ns: Namespace.ID
    var system: ShopSource.System = .kitchen
    var hidden = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(item.tint == nil ? 4.0 / 3.0 : 1, contentMode: .fit)
                .overlay { ItemArt(item: item, fill: surface) }
                .clipped()
                .matchedGeometryEffect(id: "photo-\(item.id)", in: ns, isSource: !hidden)
                .saturation(item.available ? 1 : 0)
                .overlay(alignment: .topLeading) {
                    if !item.available {
                        Text(system == .lot ? L("נמכר", in: ui) : L("נגמר", in: ui)).font(.darb(.caption, .black)).foregroundStyle(surface)
                            .padding(.horizontal, 9).padding(.vertical, 3).background(ink, in: Capsule()).padding(8)
                    } else if let b = item.badge, !b.isEmpty {
                        Text(b).font(.darb(.caption2, .black)).foregroundStyle(surface)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(accent, in: Capsule()).padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.darb(.subheadline, .heavy)).lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
                if system == .lot, let facts = item.tags, !facts.isEmpty {
                    Text(verbatim: facts.prefix(3).joined(separator: " · ")).font(.darb(.caption, .semibold)).opacity(0.65).lineLimit(1)
                }
                if let price = item.price {
                    Text(item.sizes != nil ? L("מ %@", in: ui, ShopView.money(price)) : ShopView.money(price))
                        .font(.darb(.headline, .black)).foregroundStyle(accent).monospacedDigit()
                } else {
                    Text(system == .lot ? L("התקשרו למחיר", in: ui) : L("המחיר בקרוב", in: ui)).font(.darb(.subheadline, .bold)).foregroundStyle(ink.opacity(0.5))
                }
            }
            .foregroundStyle(ink)
            .padding(10)
        }
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(accent.opacity(0.18), lineWidth: 1) }
        .opacity(hidden ? 0 : (item.available ? 1 : 0.7))
    }
}

/// The business's logo, on its own colour, inside a ring of its accent: how a partner's logo shows everywhere.
struct LogoRing: View {
    let url: URL?
    let bg: Color, accent: Color
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            Circle().fill(bg)
            KeptImage(url: url) { $0.resizable().scaledToFill() } placeholder: {
                Image("Mark").resizable().scaledToFit().padding(size * 0.22)
            }
            .clipShape(Circle())
            .padding(size * 0.06)
        }
        .frame(width: size, height: size)
        .overlay { Circle().strokeBorder(accent, lineWidth: max(2.5, size * 0.04)) }
        .overlay { Circle().strokeBorder(bg, lineWidth: 1).padding(-2) }
    }
}

/// One item, up close, opened in place: its picture grows out of its card in the grid, the shop stays visible
/// above, and everything to choose sits within reach of the thumb.
private struct ItemSheet: View {
    let item: Shop.Item
    let ink: Color, bg: Color, accent: Color
    let ui: Lang
    let ns: Namespace.ID
    var system: ShopSource.System = .kitchen
    let close: () -> Void
    let add: (Int?) -> Void
    @State private var size = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    if let gallery = item.gallery {
                        // every photo of the car, swiped
                        TabView {
                            ForEach(gallery, id: \.self) { url in
                                KeptImage(url: url, fill: bg) { $0.resizable().scaledToFill() }.clipped()
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                    } else {
                        ItemArt(item: item, fill: bg, pad: 16)
                    }
                }
                .clipped()
                .matchedGeometryEffect(id: "photo-\(item.id)", in: ns)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.symbol(.footnote)).foregroundStyle(ink)
                            .frame(width: 34, height: 34).background(bg.opacity(0.85), in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .padding(4)
                    .accessibilityLabel(L("סגירה", in: ui))
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).font(.darb(size: 24, .black, relativeTo: .title2)).lineLimit(2)
                    Spacer(minLength: 8)
                    if let price = item.price {
                        Text(ShopView.money(item.sizes?[size] ?? price)).font(.darb(size: 24, .black, relativeTo: .title2))
                            .foregroundStyle(accent).monospacedDigit().contentTransition(.numericText())
                    }
                }
                if let line = item.line, line != item.name {
                    Text(verbatim: line).font(.darb(.subheadline, .bold)).opacity(0.6)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            if let n = item.note { Text(n).font(.darb(.subheadline)).opacity(0.75).fixedSize(horizontal: false, vertical: true) }
            if !(item.tags ?? []).isEmpty || item.detail != nil {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        if let d = item.detail { chip(d, strong: true) }
                        ForEach(item.tags ?? [], id: \.self) { chip($0, strong: false) }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if let sizes = item.sizes {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { i in
                        let on = size == i
                        Button { withAnimation(.snappy) { size = i }; Haptic.tap() } label: {
                            VStack(spacing: 0) {
                                Text(verbatim: ["S", "M", "L"][i]).font(.darb(.headline, .black))
                                Text(ShopView.money(sizes[i])).font(.darb(.caption, .bold)).monospacedDigit()
                            }
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .foregroundStyle(on ? bg : ink)
                            .background(on ? accent : ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(PressStyle(scale: 0.95))
                    }
                }
            }
            let asks = system == .lot
            let orderable = item.available && (asks || item.price != nil)
            Button { add(item.sizes == nil ? nil : size) } label: {
                HStack {
                    Image(systemName: asks ? (orderable ? "message.fill" : "checkmark.seal.fill") : orderable ? "bag.badge.plus" : item.available ? "clock" : "nosign")
                        .font(.symbol(.title3))
                    Text(asks ? (orderable ? L("לשאול בוואטסאפ", in: ui) : L("נמכר", in: ui))
                         : orderable ? L("להוסיף לסל", in: ui) : item.available ? L("המחיר בקרוב", in: ui) : L("נגמר כרגע", in: ui))
                        .font(.darb(.title3, .heavy))
                    Spacer()
                    if asks, orderable, item.price == nil {
                        Text(L("התקשרו למחיר", in: ui)).font(.darb(.caption, .bold)).opacity(0.75)
                    }
                }
                .foregroundStyle(bg).padding(.horizontal, 22).frame(height: 58)
                .background(orderable ? accent : ink.opacity(0.3), in: Capsule())
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .disabled(!orderable)
        }
        .foregroundStyle(ink)
        .padding(14)
        .background(bg, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(accent.opacity(0.3), lineWidth: 1) }
        .gesture(DragGesture().onEnded { g in if g.translation.height > 80 { close() } })
    }

    private func chip(_ text: String, strong: Bool) -> some View {
        Text(verbatim: text).font(.darb(.caption, .bold))
            .foregroundStyle(strong ? bg : ink)
            .padding(.horizontal, 10).frame(height: 28)
            .background(strong ? ink : ink.opacity(0.08), in: Capsule())
    }
}

/// The bag: what was picked, how many, and the order sent to the business, written out on WhatsApp.
private struct BagSheet: View {
    @Binding var lines: [BagLine]
    let ink: Color, bg: Color, accent: Color
    let ui: Lang
    let name: String
    let minOrder: Double?
    let note: String?
    let send: () -> Void
    var body: some View {
        let total = lines.reduce(0) { $0 + $1.price * Double($1.qty) }
        let lack = (minOrder ?? 0) - total
        VStack(alignment: .leading, spacing: 14) {
            Text(L("הסל שלי", in: ui)).font(.darb(size: 28, .black, relativeTo: .title))
            ScrollView {
                VStack(spacing: 10) {
                    ForEach($lines) { $l in
                        HStack(spacing: 12) {
                            ItemArt(item: l.item, fill: ink.opacity(0.08), pad: 4)
                                .frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.item.name + (l.size.map { " · " + ["S", "M", "L"][$0] } ?? "")).font(.darb(.subheadline, .heavy)).lineLimit(1)
                                Text(ShopView.money(l.price)).font(.darb(.caption, .bold)).foregroundStyle(accent)
                            }
                            Spacer()
                            Stepper(value: $l.qty, in: 0...20) { Text(verbatim: "\(l.qty)").font(.darb(.headline, .black)).monospacedDigit() }
                                .fixedSize()
                        }
                    }
                }
            }
            if lack > 0, let m = minOrder {
                Label(L("ההזמנה המינימלית %@. חסרים עוד %@.", in: ui, ShopView.money(m), ShopView.money(lack)), systemImage: "info.circle.fill")
                    .font(.darb(.footnote, .bold)).foregroundStyle(accent)
            }
            Button(action: send) {
                HStack {
                    Image(systemName: "paperplane.fill").font(.symbol(.title3))
                    Text(L("לשלוח את ההזמנה ל%@", in: ui, name)).font(.darb(.headline, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Text(ShopView.money(total)).font(.darb(.title3, .black)).monospacedDigit()
                }
                .foregroundStyle(bg).padding(.horizontal, 22).frame(height: 62)
                .background(lack > 0 ? ink.opacity(0.3) : accent, in: Capsule())
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .disabled(lack > 0)
            Text(note.flatMap { $0.isEmpty ? nil : $0 } ?? L("ההזמנה נשלחת לעסק בוואטסאפ, כתובה ומוכנה. התשלום אצלם.", in: ui))
                .font(.darb(.caption)).opacity(0.6)
        }
        .foregroundStyle(ink)
        .padding(20)
        .onChange(of: lines) { lines.removeAll { $0.qty == 0 } }
    }
}
