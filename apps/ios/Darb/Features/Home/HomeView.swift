import SwiftUI

/// The landing screen: the valley at this hour, then every everyday need already answered.
/// It is one screen and taps only: nothing here scrolls, swipes or drags.
struct HomeView: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Binding var path: NavigationPath
    /// The menu, or one of its pages, when it is open. It is owned above this screen, so a change of language does not close it.
    @Binding var menu: MenuStart?
    let igniteAt: Date?

    @Namespace private var zoom
    @State private var shownOpen = 0
    @State private var showSearch = false
    @State private var showKinds = false
    @State private var showTown = false
    @State private var openedSheet = false
    /// How far down the header's text reaches, measured; the hills begin under it.
    @State private var headerBottom: CGFloat = 0
    @State private var pending: Route?
    /// The place being walked to, in the valley.
    @State private var walkTo: Entry?

    /// On iOS 26 search lives in the tab bar, Apple's own way; before that the screen keeps its own search field.
    private var ownSearch: Bool { if #available(iOS 26, *) { false } else { true } }

    var body: some View {
        let firsts = store.firsts()
        let lead = store.lead(among: firsts)
        // the eight tiles keep one order at every hour, so a need is always where the hand remembers it;
        // only the lead card changes with the hour
        let rest = Need.all.filter { $0.key != lead.need.key }.compactMap { n in firsts.first { $0.need.key == n.key } }
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top, bottom = geo.safeAreaInsets.bottom
            let full = geo.size.height + top + bottom
            let compact = full < 880
            VStack(spacing: 0) {
                let header = headerBottom > 0 ? headerBottom : top + 118
                valley(height: max((full * (compact ? 0.29 : 0.31)).rounded(), header + (compact ? 110 : 120)), top: top, header: header, compact: compact, focus: lead.entry?.id)
                // the towns run past between the valley and the needs, like a departure board
                TownTicker()
                sheet(lead: lead, firsts: firsts, rest: rest, compact: compact, bottom: bottom)
            }
            .ignoresSafeArea()
        }
        .background(Color.canvas)
        .navigationDestination(for: Route.self) { r in
            if let q = store.query(r) {
                PlaceView(query: q, flies: r.isNeed, open: { path.append($0) }, plans: { menu = MenuStart(.plans) })
                    .modifier(ZoomIn(route: r, ns: zoom))
            }
        }
        .sheet(isPresented: $showSearch, onDismiss: flushPending) {
            SearchSheet(scope: nil) { pending = .business($0.business.id); showSearch = false }
        }
        .sheet(isPresented: $showKinds, onDismiss: flushPending) {
            KindsSheet { pending = .kind($0.slug); showKinds = false }
        }
        .sheet(isPresented: $showTown) { TownChooser() }
        .fullScreenCover(item: $walkTo) { WalkSheet(entry: $0) }
        .onAppear {
            // `-darbSheet settings` opens a sheet or a page of the menu, for screenshots and tests
            guard let sheet = UserDefaults.standard.string(forKey: "darbSheet"), !openedSheet else { return }
            openedSheet = true
            Task {
                if Perf.prints { try? await Task.sleep(for: .seconds(2.5)) }
                Perf.tap(sheet)
                switch sheet {
                case "search": showSearch = true
                case "kinds": showKinds = true
                case "town", "towns": showTown = true
                case "menu": menu = MenuStart(nil)
                case "walk":
                    while !store.isReady { try? await Task.sleep(for: .seconds(0.2)) }
                    walkTo = store.lead(among: store.firsts()).entry
                default: if let page = MenuPage(argument: sheet) { menu = MenuStart(page) }
                }
            }
        }
        .onChange(of: igniteAt, initial: true) { _, at in
            guard at != nil else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: ValleyView.igniteDuration)) { shownOpen = store.openCount }
        }
        .onChange(of: store.openCount) { _, n in if igniteAt != nil { withAnimation { shownOpen = n } } }
    }

    private func flushPending() {
        if let p = pending { path.append(p); pending = nil }
    }

    // MARK: the valley and its header

    private func valley(height: CGFloat, top: CGFloat, header: CGFloat, compact: Bool, focus: Int?) -> some View {
        let day = store.looksDay
        return ZStack(alignment: .topLeading) {
            ValleyView(igniteAt: igniteAt, focus: focus, header: header)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image("Mark").resizable().scaledToFit().frame(width: 25, height: 25)
                        .frame(width: 44, height: 44)
                        .background(Color.onColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.mustard.opacity(0.35), lineWidth: 1) }
                        .accessibilityHidden(true)
                    whereButton
                    Spacer(minLength: 0)
                    menuButton
                }
                // how many are open, as one line: the figure first, then what it counts. One line, so the two can never meet.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: shownOpen.formatted()).figure(compact ? 34 : 40, weight: .black)
                        .contentTransition(.numericText(value: Double(shownOpen)))
                        .fixedSize()
                    Text(L("מקומות פתוחים")).font(.darb(.headline, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .opacity(store.isReady ? 1 : 0)
                .accessibilityElement(children: .combine)
            }
            .foregroundStyle(day ? Color.onColor : Color(hex: 0xFBF7EC))
            .padding(.horizontal, 18)
            .padding(.top, top + 4)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("valley")).maxY.rounded() } action: { headerBottom = $0 }
        }
        .coordinateSpace(.named("valley"))
        .frame(height: height)
        .clipped()
    }

    /// Where the answers are measured from, and the way to change it: the person's position, or a town they choose.
    private var whereButton: some View {
        Button { Perf.tap("town"); showTown = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    if store.isReady {
                        Text(store.homeName).font(.darb(.title3, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Skeleton(width: 84, height: 16).frame(height: 26)
                    }
                    Image(systemName: store.isLive ? "location.fill" : "chevron.down").font(.symbol(.caption2)).opacity(0.7)
                        .symbolEffect(.pulse, options: .repeat(2), value: store.isLive)
                        .accessibilityHidden(true)
                }
                Text(verbatim: store.now.formatted(.dateTime.weekday(.wide).locale(store.lang.locale)) + " · " + OpenHours.clock(store.minuteOfDay))
                    .font(.darb(.footnote, .medium)).monospacedDigit().opacity(0.72)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.97))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(store.isLive ? L("לפי המיקום שלכם, ליד %@", store.homeName) : L("לפי ישוב שבחרתם: %@", store.homeName))
        .accessibilityHint(L("בחירת ישוב או מיקום"))
    }

    /// The way into the rest of the app: settings, plans, joining and writing to us.
    private var menuButton: some View {
        Button { Perf.tap("menu"); Haptic.tap(); menu = MenuStart(nil) } label: {
            MenuGlyph()
                .frame(width: 44, height: 44)
                .modifier(GlassTile())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel(L("תפריט"))
    }

    // MARK: the sheet of needs

    private func sheet(lead: (need: Need, entry: Entry?, reason: Store.LeadReason), firsts: [(need: Need, entry: Entry?)], rest: [(need: Need, entry: Entry?)], compact: Bool, bottom: CGFloat) -> some View {
        let gap: CGFloat = compact ? 11 : 13
        return VStack(spacing: gap) {
            ZStack(alignment: .bottomTrailing) {
                NavigationLink(value: Route.need(lead.need.key)) { LeadCard(need: lead.need, entry: lead.entry, height: compact ? 116 : 134, loading: !store.isReady, line: lead.entry.map(store.statusLine)) }
                    .buttonStyle(TileStyle(scale: 0.99))
                    .simultaneousGesture(TapGesture().onEnded { Perf.tap("need") })
                    .matchedTransitionSource(id: Route.need(lead.need.key), in: zoom) { $0.clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)) }
                if let e = lead.entry {
                    // the ways there, side by side: on foot when it is close, and by car
                    HStack(spacing: 8) {
                        Button { Analytics.log(.navigate, e.id); DriveLive.start(e, store: store); openURL(Outside.way(e.business)) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "car.fill").font(.symbol(.subheadline))
                                Text(L("נווט")).font(.darb(.subheadline, .heavy)).fixedSize()
                            }
                            .foregroundStyle(Color(hex: 0xFBF7EC))
                            .padding(.horizontal, 14).frame(height: 40)
                            .sticker(Color.onColor, radius: 20, line: 2, drop: 3)
                            .frame(height: 44).contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle(scale: 0.94))
                        .accessibilityLabel(L("לנווט אל %@", e.business.name))
                        if e.business.km < 3 {
                            Button { Haptic.tap(); walkTo = e } label: {
                                Image(systemName: "figure.walk").font(.symbol(.headline))
                                    .foregroundStyle(Color.onColor)
                                    .frame(width: 40, height: 40)
                                    .sticker(Color(hex: 0xFBF7EC), radius: 20, line: 2, drop: 3)
                                    .frame(width: 44, height: 44).contentShape(Circle())
                            }
                            .buttonStyle(PressStyle(scale: 0.9))
                            .accessibilityLabel(L("ללכת ברגל אל %@, %lld דקות", e.business.name, Geo.walkMinutes(km: e.business.km)))
                        }
                    }
                    .padding(.trailing, 10).padding(.bottom, 8)
                }
            }
            .overlay(alignment: .topLeading) { leadSwitch(lead: lead, firsts: firsts) }
            // nine tiles, one size: the rows share the height left over
            GeometryReader { grid in
                let rowH = max(0, (grid.size.height - gap * 2) / 3)
                VStack(spacing: gap) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { col in
                                let i = row * 3 + col
                                Group {
                                    if i < 8, i < rest.count {
                                        let n = rest[i].need
                                        NavigationLink(value: Route.need(n.key)) { NeedTile(need: n, entry: rest[i].entry, loading: !store.isReady) }
                                            .simultaneousGesture(TapGesture().onEnded { Perf.tap("need") })
                                            .matchedTransitionSource(id: Route.need(n.key), in: zoom) { $0.clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)) }
                                    } else {
                                        Button { Perf.tap("kinds"); showKinds = true } label: { EverythingTile(kinds: store.kindCount, places: store.near.count) }
                                    }
                                }
                                .buttonStyle(TileStyle(scale: 0.98))
                                .frame(maxWidth: .infinity)
                                .frame(height: rowH)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            if ownSearch {
                Button { Perf.tap("search"); showSearch = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.symbol(.body))
                        Text(L("מה מחפשים? עסק, מנה או ישוב")).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .font(.darb(.body))
                    .padding(.horizontal, 18)
                    .frame(height: compact ? 46 : 50)
                    .background(Color.card2, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.98))
                .accessibilityLabel(L("חיפוש עסק"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 22)
        .padding(.bottom, bottom + 10)
        .frame(maxHeight: .infinity)
        .allowsHitTesting(store.isReady)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .background { Color.sheet.ignoresSafeArea(edges: .bottom) }
    }

    /// The lead card says what it answers and why, and one touch changes it: the need's name is a menu of all nine.
    /// It follows the person's own choices and habits, never a paid placement.
    private func leadSwitch(lead: (need: Need, entry: Entry?, reason: Store.LeadReason), firsts: [(need: Need, entry: Entry?)]) -> some View {
        HStack(spacing: 8) {
            Menu {
                // a native picker: the system's own checkmark, each need with its object, and one short line
                Picker(L("מה להראות כאן"), selection: Binding(
                    get: { lead.need.key },
                    set: { key in withAnimation(reduceMotion ? nil : Motion.swap) { store.setLead(key) } }
                )) {
                    ForEach(firsts, id: \.need.key) { f in
                        Label {
                            Text(f.need.title)
                            if let e = f.entry {
                                Text(verbatim: L("%lld דק׳", e.business.minutes) + " · " + (e.status.hour.isEmpty ? e.status.short : e.status.hour))
                            }
                        } icon: {
                            if let art = ArtLibrary.shared.small(f.need.art) { Image(uiImage: art) }
                        }
                        .tag(f.need.key)
                    }
                }
                .pickerStyle(.inline)
                Section {
                    Button { withAnimation(reduceMotion ? nil : Motion.swap) { store.setLead(nil) } } label: { Label(L("לבחור בשבילי, לפי השעה וההרגל"), systemImage: "clock.arrow.circlepath") }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(lead.need.title).font(.poster(24, relativeTo: .headline)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.symbol(.caption2))
                        .symbolEffect(.bounce, value: lead.need.key)
                }
                .foregroundStyle(Color(hex: 0xFBF7EC))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .sticker(Color.onColor, radius: 17, line: 2, drop: 3)
                .rotationEffect(.degrees(-3))
                .frame(height: 44)
                .contentShape(Capsule())
            }
            .accessibilityLabel(L("הכרטיס עונה על %@. החלפה", lead.need.title))
            VStack(alignment: .leading, spacing: 0) {
                Text(lead.entry?.status.isOpen == false ? L("הכי קרוב, סגור") : L("הכי קרוב ופתוח")).font(.darb(.caption, .heavy))
                Text(lead.reason == .choice ? L("לפי הבחירה שלכם") : lead.reason == .habit ? L("לפי מה שאתם פותחים בשעה הזו") : L("לפי השעה")).font(.darb(.caption2, .semibold)).opacity(0.62)
            }
            .lineLimit(1)
            .foregroundStyle(Color.onColor)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
        }
        .padding(.leading, 12)
        .padding(.top, 4)
    }
}

/// The tile grows into its page. This is the system's own zoom: it runs at the display's full rate, it can be
/// caught and reversed mid-way, and closing is the same move backwards (the back button, a swipe from the edge,
/// or pulling the page down). The page keeps it clean by showing only what the tile and the page share while it
/// grows (see `PlaceView.landed`).
struct ZoomIn: ViewModifier {
    let route: Route
    let ns: Namespace.ID
    func body(content: Content) -> some View {
        if case .need = route {
            content.navigationTransition(.zoom(sourceID: route, in: ns))
        } else {
            content
        }
    }
}

/// A row of the index answers the touch at once: it darkens a little under the finger and the phone ticks.
struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.ink.opacity(configuration.isPressed ? 0.07 : 0))
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.2), value: configuration.isPressed)
            .sensoryFeedback(trigger: configuration.isPressed) { _, down in down ? .impact(weight: .light, intensity: 0.7) : nil }
    }
}

