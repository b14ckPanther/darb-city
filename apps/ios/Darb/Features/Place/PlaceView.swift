import SwiftUI

/// The answer to a need: the nearest place open now, as a card you can flip through.
/// The stage on top is the place itself; swipe it, or tap the row under it, to move to the next nearest.
/// Under that sits the place's own page, with the way there always in reach.
///
/// How it moves. A tile grows into this page, and what grows is exactly what the tile carried: the need's colour,
/// its object and its name. Nothing in that picture changes while anything is moving. The page arrives as the
/// need's own title card. Then the rest of the page appears under it (`landed`). Only when everything is still does
/// the title card give way, where it stands, to the nearest place: its name, and its own picture when that is a
/// different one (`resolved`). Leaving is the same backwards: the place gives the stage back to the need first,
/// and the need's card is what shrinks into the tile. Turning to another place also changes the stage where it stands.
struct PlaceView: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    let query: PlaceQuery
    /// The page is opened by a tile growing into it, so its content waits for the growth to finish.
    var flies = false
    let open: (Route) -> Void
    /// Opens Darb's plans, from the cards that invite a business to appear here.
    var plans: () -> Void = {}

    enum Tab: Hashable { case page, hours, info }

    @State private var all: [Entry] = []
    @State private var town: String?
    @State private var selected: Int?
    /// The page has arrived and the content under the stage is showing.
    @State private var landed = false
    /// The content under the stage exists. It is made once the page is on its way, and stays.
    @State private var built = false
    /// That content has finished its small rise. It rises only on the way in; on the way out it just fades.
    @State private var risen = false
    /// The stage shows the place. Until then it is the need's own title card, the one that grew out of the tile.
    @State private var resolved = true
    /// The page has scrolled past its stage: the bar at the top carries the place's name instead.
    @State private var folded = false
    @Environment(\.layoutDirection) private var direction
    /// The way in has finished, so coming back to this page (from a place opened from it) may resolve the stage again.
    @State private var arrived = false
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .page
    @State private var showTowns = false
    @State private var showFind = false
    @State private var pending: Route?
    @State private var web: WebPage?
    /// The place being walked to, in the walking screen.
    @State private var walkTo: Entry?
    /// The Deluxe client whose own shop is open, drawn natively.
    @State private var shopFor: Business?
    @State private var savedBounce = 0
    @Namespace private var tabNS

    private var pool: [Entry] { town.map { t in all.filter { $0.business.place == t } } ?? all }

    var body: some View {
        let pool = pool
        let current = pool.first { $0.id == selected } ?? pool.first
        let profile = current.flatMap { store.profile($0.id) }
        // until the stage shows the place it keeps the need's own colours, whatever the place's are
        let style = StageStyle(query: query, profile: profile, art: current.map { store.art(for: $0.business) }, cover: current?.business.cover)
        // a business's own page shows what the business itself published. A stand-in page exists only for a demo profile.
        let tabs = tabs(paid: store.isPaid(profile) && (profile?.items.isEmpty == false || profile?.demo == true))
        let sponsor = town == nil ? store.pageSponsor(kinds: query.kinds, nearest: all.first { $0.id != query.pinned } ?? all.first) : nil
        let tab = tabs.contains { $0.0 == self.tab } ? self.tab : tabs[0].0
        ScrollView {
            VStack(spacing: 0) {
                // the swipe lives in a small view of its own, so a drag redraws only the stage, never the whole page
                SwipeStage(canTurn: { canTurn(step(for: $0), in: pool, from: current) },
                           commit: { turn(step(for: $0), in: pool, from: current) },
                           still: reduceMotion) { drag in
                    stage(pool: pool, current: current, style: style, drag: drag)
                }
                // What is under the stage is not on screen while the tile grows into the page, so it is not built
                // until then either: the page starts moving with only its stage to make.
                if built || !flies {
                VStack(alignment: .leading, spacing: 14) {
                    whereRow(pool: pool)
                    rail(pool: pool, current: current, sponsor: sponsor)
                    if let e = current {
                        if let look = DeluxeLook.of(e.business.id, lang: store.lang) {
                            ShopDoorCard(look: look, name: look.shop?.name ?? e.business.name) { shopFor = e.business }
                                // the shop's pictures start loading the moment its page opens, before anyone taps in
                                .task(id: e.business.id) { await ShopLoader.warm(look.shop) }
                        }
                        photos(e, profile: profile)
                        tabBar(tabs, tab: tab)
                        PlacePanel(entry: e, query: query, tab: tab, profile: profile, accent: style.accentOnCanvas, open: { web = WebPage($0) }, plans: plans)
                            .id("\(e.id)-\(tab)")
                            // the new panel fades in where it stands; the old one only fades
                            .transition(.opacity)
                    } else {
                        empty
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .opacity(landed ? 1 : 0)
                .offset(y: risen || reduceMotion ? 0 : Motion.rise)
                }
            }
            .animation(reduceMotion ? nil : Motion.swap, value: current?.id)
            .animation(reduceMotion ? nil : Motion.swap, value: tab)
        }
        .scrollBounceBehavior(.basedOnSize)
        // past the stage the bar at the top takes the stage's colour and the place's name, the way Music does
        .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 250 }) { _, f in
            withAnimation(.easeOut(duration: 0.18)) { folded = f }
        }
        .background(Color.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) { if built || !flies, let e = current { dock(e, style: style, profile: profile).opacity(landed ? 1 : 0) } }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(style.wash, for: .navigationBar)
        .toolbarBackground(folded ? .visible : .hidden, for: .navigationBar)
        .toolbar {
            if let e = current {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        ArtThumb(art: store.art(for: e.business), size: 26)
                        Text(e.business.name).font(.darb(.subheadline, .heavy)).lineLimit(1)
                    }
                    .foregroundStyle(style.ink)
                    .opacity(folded ? 1 : 0)
                    .offset(y: folded ? 0 : 8)
                    .accessibilityHidden(!folded)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    let kept = store.isSaved(e.id)
                    Button { store.toggleSaved(e.id); savedBounce += 1; Haptic.tap() } label: {
                        Image(systemName: kept ? "bookmark.fill" : "bookmark")
                            .symbolEffect(.bounce, value: savedBounce)
                    }
                    .accessibilityLabel(kept ? L("להסיר מהשמורים") : L("לשמור את %@", e.business.name))
                    ShareLink(item: Outside.shareLink(e.business), subject: Text(e.business.name),
                              message: Text(L("%@, %@. הדרך לשם:", e.business.name, store.placeName(e.business.place)))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L("לשתף את %@", e.business.name))
                }
            }
        }
        .fullScreenCover(item: $walkTo) { WalkSheet(entry: $0) }
        .fullScreenCover(item: $shopFor) { b in
            if let s = ShopSource.all[b.id] { ShopView(business: b, source: s) }
        }
        .onAppear {
            // `-darbShop YES` with a business route opens its shop at once, for screenshots
            if UserDefaults.standard.bool(forKey: "darbShop"), let p = query.pinned, let b = store.business(p), ShopSource.all[p] != nil { shopFor = b }
        }
        .sheet(isPresented: $showTowns) {
            TownPicker(title: query.title, color: query.color, entries: all, selected: town) { t in
                showTowns = false
                withAnimation(reduceMotion ? nil : Motion.swap) { town = t; selected = nil }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showFind, onDismiss: { if let p = pending { pending = nil; open(p) } }) {
            SearchSheet(scope: query.kinds, title: query.title) { pending = .business($0.business.id); showFind = false }
        }
        .webPage($web)
        // the data arrived, or the person moved, while the page was open
        .onChange(of: store.near.count) { if all.isEmpty { all = store.entries(kinds: query.kinds, pinned: query.pinned) } }
        .onAppear {
            Perf.shown(query.pinned != nil ? "business" : query.need != nil && query.kinds == query.need?.kinds ? "need" : "kind")
            if all.isEmpty {
                all = store.entries(kinds: query.kinds, pinned: query.pinned)
                // opening a need's own page is what teaches the lead card what this person wants at this hour
                if let n = query.need, query.pinned == nil, query.kinds == n.kinds { store.noteOpened(need: n.key) }
            }
            if UserDefaults.standard.string(forKey: "darbSheet") == "towns" { showTowns = true }
            if let t = UserDefaults.standard.string(forKey: "darbTab") { self.tab = t == "hours" ? .hours : t == "info" ? .info : .page }
            if let first = all.first { Analytics.log(.open, first.id) }
            // `-darbPick 3` turns the stage to the third place, for testing
            let n = UserDefaults.standard.integer(forKey: "darbPick")
            if n > 1, all.indices.contains(n - 1) {
                let id = all[n - 1].id
                Task { try? await Task.sleep(for: .seconds(0.8)); select(id) }
            }
        }
        // A page that grew out of a tile closes with its own back button, so that its content can leave first.
        // Swiping back from the edge and pulling the page down still work: they belong to the zoom itself.
        .navigationBarBackButtonHidden(flies)
        .background {
            if flies {
                // a swipe or a pull that starts to close the page hands the stage back to the need at once,
                // so what shrinks into the tile is the tile's own picture; if the gesture is let go, the place returns
                KeepBackSwipe(leaving: {},
                              returned: {})
            }
        }
        .toolbar {
            if flies {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) { Image(systemName: "chevron.backward") }
                        .accessibilityLabel(L("חזרה"))
                }
            }
        }
        .task {
            guard !arrived else { return }
            guard flies, !reduceMotion else {
                built = true; landed = true; risen = true; arrived = true
                return await autoBack()
            }
            // 1. the tile grows into the page: only the need's own card is on it. The rest is made meanwhile, unseen
            try? await Task.sleep(for: .seconds(0.1))
            built = true
            try? await Task.sleep(for: .seconds(Motion.flight - 0.1))
            // 2. the rest of the page appears under the card, with a short fade and a small rise
            withAnimation(Motion.land) { landed = true; risen = true }
            arrived = true
            await autoBack()
        }
    }

    /// `-darbAutoBack 2.2` closes the page again, to film the way out.
    private func autoBack() async {
        let back = UserDefaults.standard.double(forKey: "darbAutoBack")
        if back > 0 { try? await Task.sleep(for: .seconds(back)); close() }
    }

    /// Leaving is arriving backwards: the place gives the stage back to the need and the content under it fades,
    /// all where it stands, and only then does the need's card shrink back into its tile.
    private func close() {
        Perf.tap("back")
        // back is immediate: the system's own zoom carries the page back into its tile from wherever it is
        dismiss()
    }

    /// A sideways swipe on the stage turns it to the next place, or back to the one before.
    private func turn(_ step: Int, in pool: [Entry], from current: Entry?) {
        guard let c = current, let i = pool.firstIndex(where: { $0.id == c.id }), pool.indices.contains(i + step) else { return }
        select(pool[i + step].id)
    }

    /// Which way a sideways swipe turns: in a right to left language the next place lies to the left, so it is
    /// pulled in by a swipe to the right; in English the other way round.
    private func step(for dx: CGFloat) -> Int {
        let forward = direction == .rightToLeft ? 1 : -1
        return dx > 0 ? forward : -forward
    }

    private func canTurn(_ step: Int, in pool: [Entry], from current: Entry?) -> Bool {
        guard let c = current, let i = pool.firstIndex(where: { $0.id == c.id }) else { return false }
        return pool.indices.contains(i + step)
    }

    /// A free listing has its hours and its details. A menu, prices or services are what a paid page adds.
    private func tabs(paid: Bool) -> [(Tab, String)] {
        var t: [(Tab, String)] = []
        if paid { t.append((.page, query.need?.pageName ?? L("מהעסק"))) }
        t += [(.hours, L("שעות")), (.info, L("פרטים"))]
        return t
    }

    private func select(_ id: Int) {
        if id != selected { Analytics.log(.open, id) }
        selected = id
        Haptic.tap()
    }

    // MARK: the stage

    private func stage(pool: [Entry], current: Entry?, style: StageStyle, drag: CGFloat) -> some View {
        let index = current.flatMap { c in pool.firstIndex { $0.id == c.id } } ?? 0
        /// The stage shows the place; otherwise it is the need's title card.
        let shows = resolved || !flies
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(query.title)
                if pool.count > 1 {
                    Group {
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text(L("%lld מתוך %lld", index + 1, pool.count)).monospacedDigit().contentTransition(.numericText(value: Double(index)))
                    }
                    .opacity(shows ? 1 : 0)
                }
            }
            .eyebrow()
            .opacity(0.62)
            .padding(.horizontal, 20)

            // one place at a time, changing where it stands: the name never slides past the object beside it
            ZStack(alignment: .topLeading) {
                if let e = current {
                    PlaceFace(entry: e, style: style, profile: store.profile(e.id), remind: { toggleReminder(e) },
                              next: e.late ? pool.first(where: { $0.status.isOpen && !$0.late }).map { n in { select(n.id) } } : nil)
                        .id(e.id)
                        // a place takes another's place where it stands: nothing moves while the picture beside it changes
                        .transition(.opacity)
                        .opacity(shows ? 1 : 0)
                        .accessibilityHidden(!shows)
                }
            }
            .environment(\.layoutDirection, direction)
            .offset(x: drag)
            .opacity(1 - min(0.7, Double(abs(drag)) / 260))
            .environment(\.layoutDirection, .leftToRight)
            .padding(.leading, 20)
            .padding(.trailing, 156)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // one height for every place, so the stage never jumps; the taller of the three scripts gets a little more
            .frame(height: store.lang == .ar ? 138 : 126, alignment: .topLeading)
            .contentShape(Rectangle())
            .accessibilityAdjustableAction { direction in turn(direction == .increment ? 1 : -1, in: pool, from: current) }

            if let e = current {
                stats(e, style: style)
                    .padding(.horizontal, 20)
                .opacity(shows ? 1 : 0)
                .accessibilityHidden(!shows)
            }
        }
        .foregroundStyle(style.ink)
        .padding(.top, 2)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // the field runs up under the status bar, and a plain wash of it covers the pull-down beyond that
            ZStack {
                style.wash.padding(.top, -900)
                style.field.padding(.top, -150)
            }
            .clipShape(StageShape())
        }
        .overlay(alignment: .topTrailing) {
            // The picture is the place's own: a pizza for a pizzeria, a burger for a burger bar.
            // On the need's title card it is the need's own object, the one the tile carried, and it stays that way
            // for as long as anything moves. When the stage resolves it gives way, where it stands and by a plain
            // crossfade, to the place's own, and only when that is a different one.
            ZStack {
                if let e = current {
                    let own = store.art(for: e.business)
                    // while the tile is still growing into the page it keeps the tile's object, so nothing swaps
                    // mid-flight; once the page has settled it is the place's own, the same as its card in the rail
                    let art = own.logo == nil && !query.art.isEmpty && flies && !resolved ? ArtRef(render: query.art, symbol: own.symbol, tint: own.tint) : own
                    // a partner's page carries their own logo, ringed; everyone else's the object on a sticker plate
                    if let look = DeluxeLook.of(e.business.id, lang: store.lang) {
                        LogoRing(url: look.shop?.logo, bg: look.bg, accent: look.accent, size: 136)
                            .padding(.top, 8)
                            .id(e.id)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    } else {
                    ZStack {
                        Circle().fill(Color(hex: 0xFBF7EC))
                            .overlay { Circle().strokeBorder(Color.onColor, lineWidth: 3) }
                            .background { Circle().fill(Color.onColor).offset(y: 5) }
                            .frame(width: 136, height: 136)
                        HeroArt(art: art, ink: style.ink, size: 150)
                            .rotationEffect(.degrees(-8))
                            .offset(y: -6)
                    }
                    .id(art)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
            }
            .offset(x: drag * 1.15)
            .opacity(1 - min(0.7, Double(abs(drag)) / 260))
            .environment(\.layoutDirection, .leftToRight)
            // scrolling away, the object shrinks a little towards its corner as the stage leaves
            .scrollTransition(.interactive, axis: .vertical) { c, phase in
                c.scaleEffect(phase.isIdentity ? 1 : 0.82, anchor: .topTrailing).opacity(phase.value < 0 ? 0.5 : 1)
            }
            .padding(.top, 34).padding(.trailing, 14)
            .padding(.trailing, 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The three facts about the way there: how long, how far, and which way.
    /// How far, in the home screen's grammar: the minutes as one large figure, and under it the distance and the
    /// direction in a single quiet line. No box around it.
    private func stats(_ e: Entry, style: StageStyle) -> some View {
        let b = e.business
        let bearing = store.bearing(to: b)
        return HStack(alignment: .lastTextBaseline, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(verbatim: "\(b.minutes)").font(.darb(size: 64, .black, relativeTo: .largeTitle)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(b.minutes)))
                Text(L("דק׳")).font(.darb(size: 18, .bold, relativeTo: .title3))
            }
            HStack(spacing: 6) {
                Image(systemName: "location.north.fill").font(.symbol(size: 12))
                    .rotationEffect(.radians(bearing))
                    .environment(\.layoutDirection, .leftToRight)
                Text(verbatim: Geo.distance(b.km) + " · " + Geo.wind(bearing)).font(.darb(size: 15, .semibold, relativeTo: .body)).lineLimit(1)
            }
            .opacity(0.72)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("%lld דקות נסיעה, %@, לכיוון %@", b.minutes, Geo.distance(b.km), Geo.wind(bearing)))
    }

    private func toggleReminder(_ e: Entry) {
        let b = e.business
        if store.hasReminder(b.id) {
            Reminder.cancel(b.id)
            store.setReminder(b.id, on: false)
            Haptic.tap()
        } else if let at = OpenHours.nextOpening(b.hours, after: store.now) {
            Task {
                if await Reminder.schedule(b, at: at) {
                    store.setReminder(b.id, on: true)
                    Haptic.done()
                }
            }
        }
    }

    // MARK: where, and the others

    private func whereRow(pool: [Entry]) -> some View {
        let open = pool.filter { $0.status.isOpen }.count
        return HStack(spacing: 8) {
            Button { showTowns = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.symbol(.subheadline))
                    Text(town.map(store.placeName) ?? L("קרוב אליי")).font(.darb(.subheadline, .bold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.symbol(.caption2)).opacity(0.5)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.card, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(L("בחירת ישוב. נבחר: %@", town.map(store.placeName) ?? L("קרוב אליי")))
            VStack(alignment: .leading, spacing: 0) {
                Text(open == 0 ? L("כולם סגורים") : open == 1 ? L("אחד פתוח") : L("%lld פתוחים", open)).font(.darb(.footnote, .bold))
                Text(town == nil ? L("מתוך %lld במרחק נסיעה", pool.count) : L("מתוך %lld", pool.count)).font(.darb(.caption2, .medium)).foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.leading, 4)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button { showFind = true } label: {
                Image(systemName: "magnifyingglass").font(.symbol(.subheadline))
                    .frame(width: 44, height: 44)
                    .background(Color.card, in: Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(L("חיפוש וכל הרשימה"))
        }
    }

    /// Every place of this need, nearest open first. Tapping one turns the stage to it.
    private func rail(pool: [Entry], current: Entry?, sponsor: (sponsorship: Sponsorship, entry: Entry)?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // A lazy row: a need can have hundreds of places, and only the few cards on screen are ever built.
                // Every card has the same width, so the row knows its length and starts at its beginning.
                LazyHStack(spacing: 8) {
                    // only a business that really paid; no house advert while nobody has
                    if let s = sponsor, !s.sponsorship.demo { paidCard(s) }
                    ForEach(pool) { e in
                        let on = e.id == current?.id
                        Button { select(e.id) } label: {
                            let look = DeluxeLook.of(e.business.id, lang: store.lang)
                            HStack(spacing: 9) {
                                if let look { DeluxeLogo(look: look, size: 40) } else { ArtThumb(art: store.art(for: e.business), size: 40) }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(e.business.name).font(.darb(.subheadline, .bold)).lineLimit(1)
                                    HStack(spacing: 5) {
                                        StatusDot(status: e.status, size: 6, lit: on)
                                        Text(verbatim: L("%lld דק׳", e.business.minutes) + " · \(e.status.short)").font(.darb(.caption, .medium)).monospacedDigit().lineLimit(1)
                                            .opacity(0.7)
                                    }
                                }
                            }
                            .padding(.leading, 9).padding(.trailing, 14)
                            // one width for every card, so the lazy row knows its length and starts at its beginning
                            .frame(width: 206, alignment: .leading)
                            .frame(height: 58)
                            .foregroundStyle(look.map { $0.ink } ?? (on ? Color.canvas : Color.ink))
                            .background(look.map { $0.bg } ?? (on ? Color.ink : Color.card), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay { if let look { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(look.accent, lineWidth: on ? 2.5 : 1.5) } }
                            .overlay(alignment: .topTrailing) { if let look { DoorBadge(accent: look.accent, ink: look.onAccent).padding(6) } }
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .id(e.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.leading)
            .padding(.horizontal, -16)
            .frame(height: 58)
            .onChange(of: current?.id) { old, id in
                guard let id, old != nil else { return }
                withAnimation(reduceMotion ? nil : Motion.select) { proxy.scrollTo(id) }
            }
        }
    }

    /// The paid placement at the head of the row: a sponsor of this kind that is nearly as near as the nearest,
    /// or Darb's own card while nobody has bought the place. It is labelled, it looks different from the ranked
    /// cards, and it is not one of them: the count and the order beside it stay honest.
    @ViewBuilder private func paidCard(_ sponsor: (sponsorship: Sponsorship, entry: Entry)?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if let s = sponsor {
            let e = s.entry
            Button { Analytics.log(.sponsored, e.id); select(e.id) } label: {
                HStack(spacing: 9) {
                    ArtThumb(art: store.art(for: e.business), size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            PaidTag(text: s.sponsorship.demo ? L("ממומן · הדגמה") : L("ממומן"))
                            Text(L("%lld דק׳", e.business.minutes)).font(.darb(.caption, .bold)).monospacedDigit().opacity(0.7)
                        }
                        Text(e.business.name).font(.darb(.subheadline, .bold)).lineLimit(1)
                    }
                }
                .padding(.leading, 9).padding(.trailing, 14)
                .frame(width: 206, height: 58, alignment: .leading)
                .background(Color.lamp.opacity(0.16), in: shape)
                .overlay { shape.strokeBorder(Color.lamp.opacity(0.8), lineWidth: 1.2) }
                .contentShape(shape)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(L("ממומן. %@, %@, %lld דקות", e.business.name, e.status.text, e.business.minutes))
        } else {
            Button(action: plans) {
                VStack(alignment: .leading, spacing: 3) {
                    PaidTag(text: L("ממומן"))
                    Text(L("העסק שלכם יכול להופיע כאן")).font(.darb(.caption, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12)
                // the same width as the cards beside it, so the row starts at its beginning
                .frame(width: 206, height: 58, alignment: .leading)
                .foregroundStyle(.secondary)
                .overlay { shape.strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(Color.ink.opacity(0.22)) }
                .contentShape(shape)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(L("ממומן. העסק שלכם יכול להופיע כאן. פותח את דרב לעסקים"))
        }
    }

    /// The business's own photos: up to three on a free listing, all of them on a paid one. Nothing is shown when it has none.
    @ViewBuilder private func photos(_ e: Entry, profile: BusinessProfile?) -> some View {
        let given = profile.map(\.photos).flatMap { $0.isEmpty ? nil : $0 } ?? store.details?[e.business.id]?.photos ?? []
        if !given.isEmpty {
            // photos given in the admin are all shown; a profile's follow its plan
            let shown = profile.map { store.isPaid($0) ? given : Array(given.prefix(BusinessProfile.freePhotos)) } ?? given
            let art = store.art(for: e.business)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, name in
                        PhotoView(name: name, art: art, variant: i + 1)
                            .frame(width: shown.count == 1 ? 300 : 132, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
            .accessibilityLabel(L("תמונות של %@", e.business.name))
        }
    }

    private func tabBar(_ tabs: [(Tab, String)], tab: Tab) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.0) { t in
                let on = t.0 == tab
                Button { withAnimation(reduceMotion ? nil : Motion.select) { self.tab = t.0 } } label: {
                    Text(t.1).font(.darb(.subheadline, .bold))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .foregroundStyle(on ? Color.canvas : Color.ink.opacity(0.6))
                        .background { if on { Capsule().fill(Color.ink).matchedGeometryEffect(id: "tab", in: tabNS) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.card2, in: Capsule())
        .sensoryFeedback(.selection, trigger: tab)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text(L("אין כאן מקומות כאלה")).font(.darb(.headline))
            Text(L("אפשר לבחור ישוב אחר, או לחפש בשם.")).font(.darb(.subheadline)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: the way there

    private func dock(_ e: Entry, style: StageStyle, profile: BusinessProfile?) -> some View {
        let b = e.business
        let x = store.extra(b.id)
        let phone = x?.phone ?? profile?.phone
        let wa = x?.wa ?? profile?.whatsapp
        let chat = wa.flatMap(Outside.whatsapp)
        // ask before you drive: when the hours are not the business's own, asking is the main thing to do
        let unsure: Bool = { if case .weekly = b.hours { return b.demoHours } else { return true } }()
        // a business with its own ordering or booking keeps that beside the way there instead
        let paidAction = store.isPaid(profile) ? profile?.action : nil
        let ask: (url: URL, symbol: String)? = unsure && paidAction == nil ? (wa.flatMap(Outside.ask).map { ($0, "message.fill") } ?? phone.flatMap(Outside.phone).map { ($0, "phone.fill") }) : nil
        return HStack(spacing: 8) {
            if let ask {
                Button { Analytics.log(.call, b.id); openURL(ask.url) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: ask.symbol).font(.symbol(.subheadline))
                            .foregroundStyle(style.dock)
                            .frame(width: 38, height: 38)
                            .background(style.onDock, in: Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(L("לשאול אם פתוח")).font(.darb(.headline, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                            Text(ask.symbol == "phone.fill" ? L("שיחה, לפני שנוסעים") : L("הודעה מוכנה בוואטסאפ")).font(.darb(.caption2, .semibold)).opacity(0.7).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity).frame(height: 58)
                    .foregroundStyle(style.onDock)
                    .background(style.dock, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .accessibilityLabel(ask.symbol == "phone.fill" ? L("להתקשר אל %@ ולשאול אם פתוח", b.name) : L("לשאול את %@ בוואטסאפ אם פתוח", b.name))
                Button { Analytics.log(.navigate, b.id); DriveLive.start(e, store: store); openURL(Outside.way(b)) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "location.fill").font(.symbol(.footnote))
                        Text(verbatim: L("נווט") + " · " + L("%lld דק׳", b.minutes)).font(.darb(.subheadline, .heavy)).lineLimit(1).fixedSize()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .background(Color.card, in: Capsule())
                    .overlay { Capsule().strokeBorder(Color.ink.opacity(0.12), lineWidth: 1) }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .accessibilityLabel(L("לנווט אל %@, %lld דקות", b.name, b.minutes))
            } else {
            Button { Analytics.log(.navigate, b.id); DriveLive.start(e, store: store); openURL(Outside.way(b)) } label: {
                HStack(spacing: 10) {
                    // the storefront, when the business gave a picture of it: what to look for on arrival
                    if let front = profile?.storefront {
                        StorefrontView(name: front, initial: store.art(for: b).initial, tint: query.color, marked: false)
                            .frame(width: 42, height: 42).clipShape(Circle())
                            .overlay { Circle().strokeBorder(style.onDock.opacity(0.5), lineWidth: 1.5) }
                    } else {
                        Image(systemName: "location.fill").font(.symbol(.subheadline))
                            .foregroundStyle(style.dock)
                            .frame(width: 38, height: 38)
                            .background(style.onDock, in: Circle())
                    }
                    Text(L("נווט")).font(.darb(.title3, .heavy)).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    // the minutes give way when the row also carries an order button and two ways to reach the place
                    ViewThatFits(in: .horizontal) {
                        Text(L("%lld דק׳", b.minutes)).font(.darb(.headline, .bold)).monospacedDigit().contentTransition(.numericText(value: Double(b.minutes)))
                            .lineLimit(1).fixedSize()
                            .padding(.trailing, 10)
                        Color.clear.frame(width: 0, height: 1)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity).frame(height: 58)
                .foregroundStyle(style.onDock)
                .background(style.dock, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle(scale: 0.97))
            .accessibilityLabel(L("לנווט אל %@, %lld דקות", b.name, b.minutes))
            }
            // on foot: for a place close enough to walk to, or one a car cannot reach
            if b.km < 3 {
                Button { Analytics.log(.navigate, b.id); walkTo = e } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "figure.walk").font(.symbol(.title3))
                        Text(L("%lld דק׳", Geo.walkMinutes(km: b.km))).font(.darb(.caption2, .heavy)).monospacedDigit().lineLimit(1).fixedSize()
                    }
                    .frame(width: 58, height: 58)
                    .background(Color.card, in: Circle())
                    .overlay { Circle().strokeBorder(Color.ink.opacity(0.12), lineWidth: 1) }
                    .contentShape(Circle())
                }
                .buttonStyle(PressStyle(scale: 0.95))
                .accessibilityLabel(L("ללכת ברגל אל %@, %lld דקות", b.name, Geo.walkMinutes(km: b.km)))
            }
            // ordering and booking belong to businesses whose app or system Darb built
            if let profile, store.isPaid(profile), let action = profile.action {
                Button { Analytics.log(.order, b.id); if ShopSource.all[b.id] != nil { shopFor = b } else { web = WebPage(action.url) } } label: {
                    Text(action.title).font(.darb(.headline, .heavy))
                        .padding(.horizontal, 18)
                        .frame(height: 58)
                        .background(Color.card, in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.ink.opacity(0.12), lineWidth: 1) }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.97))
                .accessibilityHint(L("פותח את האתר של %@", b.name))
            }
            if let chat, ask?.symbol != "message.fill" {
                Button { openURL(chat) } label: { round("message.fill") }
                    .buttonStyle(PressStyle(scale: 0.97))
                    .accessibilityLabel(L("וואטסאפ אל %@", b.name))
            }
            if let p = phone, let url = Outside.phone(p), ask?.symbol != "phone.fill" {
                Button { Analytics.log(.call, b.id); openURL(url) } label: { round("phone.fill") }
                    .buttonStyle(PressStyle(scale: 0.97))
                    .accessibilityLabel(L("להתקשר אל %@", b.name))
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
        .background {
            Color.canvas.ignoresSafeArea()
                .overlay(alignment: .top) { Rectangle().fill(Color.ink.opacity(0.1)).frame(height: 1) }
        }
    }

    private func round(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.symbol(.title3))
            .frame(width: 58, height: 58)
            .background(Color.card, in: Circle())
            .overlay { Circle().strokeBorder(Color.ink.opacity(0.12), lineWidth: 1) }
    }
}

/// The stage's outline: it runs off the top of the screen, and its bottom corners are round.
struct StageShape: Shape {
    func path(in r: CGRect) -> Path {
        Path(roundedRect: CGRect(x: r.minX, y: r.minY - 900, width: r.width, height: r.height + 900),
             cornerRadii: RectangleCornerRadii(bottomLeading: Radius.stage, bottomTrailing: Radius.stage), style: .continuous)
    }
}

/// How a stage is lit: the need's colour for a listing, the business's own colours when Darb built its app or
/// site, and the business's own cover picture when it has given one.
struct StageStyle {
    let color: Color
    let palette: BusinessProfile.Palette?
    let cover: String?
    let art: ArtRef?
    let hasObject = true

    init(query: PlaceQuery, profile: BusinessProfile?, art: ArtRef?, cover: String? = nil) {
        color = query.color
        palette = profile?.palette
        self.cover = profile?.cover ?? cover
        self.art = art
    }

    /// A real cover picture is darkened for the text over it; the placeholder keeps the need's colour and ink.
    private var photo: Bool { cover.map { !Media.isDemo($0) } ?? false }
    var ink: Color { photo ? .white : palette.map { Color(hexString: $0.ink) } ?? .onColor }
    var knob: Color { palette.map { Color(hexString: $0.accent) } ?? .white }
    var accent: Color { palette.map { Color(hexString: $0.accent) } ?? ink }
    /// The colour for accents on the page under the stage.
    var accentOnCanvas: Color { palette.map { Color(hexString: $0.accent) } ?? color }
    var dock: Color { palette.map { Color(hexString: $0.accent) } ?? color }
    var onDock: Color { palette.map { Color(hexString: $0.bg) } ?? .onColor }
    var shadow: Color { (palette.map { Color(hexString: $0.bg) } ?? color).opacity(0.3) }
    /// The pill that carries the open status.
    var pill: Color { palette == nil && !photo ? .onColor : ink.opacity(0.16) }
    var onPill: Color { palette == nil && !photo ? .white : ink }
    /// The field's colour where it meets the top of the screen.
    var wash: Color { photo ? .black : palette.map { Color(hexString: $0.bg) } ?? color.mix(with: .white, by: 0.16) }

    @ViewBuilder var field: some View {
        if let cover, let art {
            PhotoView(name: cover, art: art, variant: 2)
                .blur(radius: photo ? 0 : 5)
                .overlay { if photo { Color.black.opacity(0.55) } else { Color(hexString: art.tint).opacity(0.7) } }
                .overlay(alignment: .bottomLeading) { if !photo { DemoMark().padding(8) } }
        } else if let p = palette {
            let bg = Color(hexString: p.bg)
            Rectangle().fill(bg)
        } else {
            ColorField(color: color)
        }
    }
}

/// One place on the stage: its name, what and where it is, and whether it is open.
struct PlaceFace: View {
    @Environment(Store.self) private var store
    let entry: Entry
    let style: StageStyle
    let profile: BusinessProfile?
    let remind: () -> Void
    /// Turns the stage to the nearest place that will still be open on arrival, when this one will not be.
    var next: (() -> Void)? = nil

    var body: some View {
        let b = entry.business
        let n = b.name.count
        VStack(alignment: .leading, spacing: 0) {
            if let profile, store.isPaid(profile) {
                Label(profile.demo ? L("עמוד מלא · הדגמה") : L("עמוד רשמי"), systemImage: "checkmark.seal.fill")
                    .font(.darb(.caption2, .heavy))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(style.accent)
                    .padding(.bottom, 3)
            }
            Text(b.name)
                .display(n <= 10 ? 38 : n <= 13 ? 32 : n <= 24 ? 25 : 20)
                .lineLimit(2).minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(profile?.tagline ?? store.tagline(b))
                .font(.darb(.subheadline, .semibold)).opacity(0.7).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, 2)
                .padding(.bottom, 10)
            HStack(spacing: 6) {
                HStack(spacing: 7) {
                    if entry.late {
                        Image(systemName: "exclamationmark.triangle.fill").font(.symbol(.caption2)).foregroundStyle(Color(hex: 0xFFB547)).accessibilityHidden(true)
                    } else {
                        StatusDot(status: entry.status, size: 8, lit: true)
                    }
                    Text(store.statusLine(entry)).font(.darb(.footnote, .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .foregroundStyle(style.onPill)
                .background(style.pill, in: Capsule())
                .accessibilityElement(children: .combine)
                if let next {
                    Button(action: next) {
                        Image(systemName: "arrow.forward").font(.symbol(.footnote))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(style.pill)
                            .background(style.onPill, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressStyle(scale: 0.9))
                    .padding(.vertical, -5)
                    .accessibilityLabel(L("למקום הקרוב שעוד יהיה פתוח כשתגיעו"))
                }
                if !entry.status.isOpen, !b.demoHours, OpenHours.nextOpening(b.hours, after: store.now) != nil {
                    let on = store.hasReminder(b.id)
                    Button(action: remind) {
                        Image(systemName: on ? "bell.badge.fill" : "bell")
                            .font(.darb(.footnote, .heavy))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(on ? style.pill : style.ink)
                            .background(on ? AnyShapeStyle(style.onPill) : AnyShapeStyle(style.ink.opacity(0.1)), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressStyle(scale: 0.9))
                    .padding(.vertical, -5)
                    .accessibilityLabel(on ? L("לבטל את התזכורת") : L("להזכיר לי כשנפתח"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The stage's sideways swipe. The place follows the finger one to one; a light flick or half a short drag turns
/// it, and the next place glides in from the far side. Only this view redraws while the finger moves.
struct SwipeStage<Content: View>: View {
    /// Whether a swipe this way (a horizontal distance) has a place to turn to.
    let canTurn: (CGFloat) -> Bool
    /// Turns the page to the next place the way of this distance.
    let commit: (CGFloat) -> Void
    var still = false
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var drag: CGFloat = 0
    @State private var axis: Bool?

    var body: some View {
        content(drag)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { g in
                        // decide once per touch whether this is a sideways swipe or a scroll
                        if axis == nil { axis = abs(g.translation.width) > abs(g.translation.height) }
                        guard axis == true else { return }
                        let w = g.translation.width
                        drag = canTurn(w) ? w : w * 0.25
                    }
                    .onEnded { g in
                        defer { axis = nil }
                        guard axis == true else { return }
                        let w = g.translation.width, fling = g.predictedEndTranslation.width
                        let go = (abs(w) > 70 || abs(fling) > 160) && canTurn(w != 0 ? w : fling)
                        guard go else {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) { drag = 0 }
                            return
                        }
                        if still { drag = 0; commit(w); return }
                        let out: CGFloat = w > 0 ? 200 : -200
                        withAnimation(.easeOut(duration: 0.07)) { drag = out } completion: {
                            var quiet = Transaction(); quiet.disablesAnimations = true
                            withTransaction(quiet) { commit(w); drag = -out * 0.5 }
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) { drag = 0 }
                        }
                    }
            )
    }
}
