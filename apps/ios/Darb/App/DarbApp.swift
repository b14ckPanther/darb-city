import SwiftUI
import WidgetKit

@main
struct DarbApp: App {
    // the bundled data is read in the background; the home screen is on at once, with its shape, and fills in
    @State private var store = Store(background: true)

    init() { ArtLibrary.shared.warm() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                // text that names no font of its own is still set in the language's face
                .font(.darb(.body))
                // the home screen has to fit one screen; past this size the system would crop it
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
    }
}

/// The system's own bars and bar buttons, set in the language's face too, so no screen falls back to the system font.
@MainActor
enum SystemType {
    static func apply() {
        let large = UIFont(name: Typeface.name(.heavy), size: 34) ?? .systemFont(ofSize: 34, weight: .heavy)
        let title = UIFont(name: Typeface.name(.bold), size: 17) ?? .systemFont(ofSize: 17, weight: .bold)
        let button = UIFont(name: Typeface.name(.semibold), size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        nav.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title)]
        let item = UIBarButtonItemAppearance()
        item.normal.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .body).scaledFont(for: button)]
        nav.buttonAppearance = item
        nav.doneButtonAppearance = item
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = nav
        bar.scrollEdgeAppearance = nav
        bar.compactAppearance = nav
        UIBarButtonItem.appearance().setTitleTextAttributes([.font: button], for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont(name: Typeface.name(.semibold), size: 14) as Any], for: .normal)
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var path = NavigationPath()
    @State private var splash = !UserDefaults.standard.bool(forKey: "darbSkipSplash")
    /// The first run: what Darb is, the language, and where the person is. `-darbOnboard YES` shows it again.
    @State private var onboarding = UserDefaults.standard.bool(forKey: "darbOnboard") || !UserDefaults.standard.bool(forKey: "darbOnboarded")
    @State private var igniteAt: Date?
    /// The menu lives here, above the part that is rebuilt when the language changes, so it stays open through the change.
    @State private var menu: MenuStart?
    @State private var pending: Route?
    /// A screen asked for (by the widget, a link or a testing argument) before the data was in.
    @State private var waiting: Route?
    /// The opening's dark field has begun to fold into the header.
    @State private var closing = false
    /// The opening has been told to end, by its clock or by a tap.
    @State private var ending = false

    /// Ends the opening once, whichever asks first.
    private func endSplash() async {
        guard splash, !ending else { return }
        ending = true
        if onboarding || reduceMotion {
            // nothing travels: the field simply clears
            withAnimation(.easeOut(duration: 0.2)) { splash = false }
            if !onboarding { arrive() }
            return
        }
        // one move: the field folds into the mark's tile in the header, and the valley wakes as it opens
        arrive()
        withAnimation(SplashView.fold) { closing = true }
        try? await Task.sleep(for: .seconds(SplashView.foldTime))
        withAnimation(.easeOut(duration: 0.12)) { splash = false }
    }

    var body: some View {
        ZStack {
            DarbTabs(path: $path, menu: $menu, igniteAt: igniteAt)
                // a new language redraws everything in its own letters and direction; the stack keeps its place
                .id(store.lang)
            .foregroundStyle(Color.ink)
            if onboarding, !splash {
                OnboardingView(finish: finishOnboarding)
                    .id(store.lang)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if splash {
                SplashView(closing: closing, skip: { Task { await endSplash() } })
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .sheet(item: $menu, onDismiss: { if let p = pending { pending = nil; path.append(p) } }) { start in
            MenuSheet(start: start.page) { pending = $0; menu = nil }
        }
        .task {
            guard splash else { if !onboarding { arrive() }; return }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : SplashView.hold))
            await endSplash()
        }
        // who is open changes with the clock: once a minute, on the minute
        .task {
            while !Task.isCancelled {
                let wait = 60 - Calendar.current.component(.second, from: .now)
                try? await Task.sleep(for: .seconds(wait))
                // drives that are long over leave the Lock Screen
                if phase == .active { DriveLive.tidy() }
                // the minute turns: counts and minutes roll to their new values instead of jumping
                if phase == .active { withAnimation(.smooth(duration: 0.5)) { store.refresh() } }
            }
        }
        .onChange(of: store.isReady) { _, ready in if ready, let r = waiting { waiting = nil; show(r) } }
        // `-darbDrive YES` starts a drive to the nearest food place, to see the Live Activity without tapping
        .onChange(of: store.isReady) { _, ready in
            if ready, UserDefaults.standard.bool(forKey: "darbDrive"), let food = Need.all.first,
               let e = store.entries(kinds: food.kinds, pinned: nil).first { DriveLive.start(e, store: store) }
        }
        .onChange(of: phase) { _, p in
            if p == .active {
                store.refresh()
                // the map follows the website's database: what was added or edited in the admin arrives here
                Task { if let fresh = await LiveData.sync() { store.adopt(fresh); WidgetCenter.shared.reloadAllTimelines() } }
            }
            if p == .background { WidgetCenter.shared.reloadAllTimelines() }
        }
        .onChange(of: store.lang) { SystemType.apply(); WidgetCenter.shared.reloadAllTimelines() }
        .onAppear { SystemType.apply(); Perf.watchMainThread() }
        // partners' shops are read once at launch, quietly, so their cards carry their photos and their shop opens at once
        .task {
            // their pictures are saved on the phone once (ImageStore), so they never load one by one again
            URLCache.shared = URLCache(memoryCapacity: 16 << 20, diskCapacity: 100 << 20)
            // a staff session kept from last time, and what it may do
            Task { await Account.shared.restore() }
            for id in ShopSource.all.keys {
                if let shop = try? await ShopLoader.fetch(id, lang: ShopLang(store.lang)) { await ShopLoader.warm(shop) }
            }
        }
        .onChange(of: store.here) { WidgetCenter.shared.reloadAllTimelines() }
        // the widget opens a need: darb://need/food, darb://kind/schools, darb://business/12
        .onOpenURL { url in
            guard url.scheme == "darb", let kind = url.host() else { return }
            let value = url.lastPathComponent
            let route: Route? = kind == "need" ? .need(value) : kind == "kind" ? .kind(value) : Int(value).map(Route.business)
            if let route { show(route) }
        }
        .environment(\.layoutDirection, store.lang.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.locale, store.lang.locale)
        .preferredColorScheme(store.looksDay ? .light : .dark)
        .foregroundStyle(Color.ink)
        .tint(Color.ink)
    }

    /// The home screen is in front: the valley wakes, and a testing argument may open a screen.
    private func arrive() {
        igniteAt = .now.addingTimeInterval(0.2)
        openFromLaunchArguments()
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "darbOnboarded")
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35)) { onboarding = false }
        arrive()
    }

    /// `-darbRoute need:fuel`, `kind:schools` or `business:123` opens that screen, for screenshots and tests.
    private func openFromLaunchArguments() {
        guard let raw = UserDefaults.standard.string(forKey: "darbRoute") else { return }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        // `-darbAutoBack 2.2` waits a moment on the home screen before opening the screen; the page then closes
        // itself after that many seconds: the way in and the way out, for filming the transition
        let route: Route? = parts[0] == "need" ? .need(parts[1]) : parts[0] == "kind" ? .kind(parts[1]) : Int(parts[1]).map(Route.business)
        guard let route else { return }
        let back = UserDefaults.standard.double(forKey: "darbAutoBack")
        // when filming or timing, the screen opens once the home screen has settled
        guard back > 0 || Perf.prints else { return show(route) }
        Task {
            try? await Task.sleep(for: .seconds(back > 0 ? 1.5 : 2.5))
            Perf.tap(parts[0])
            show(route)
        }
    }

    /// Opens a screen, as soon as there is data to show on it.
    private func show(_ route: Route) {
        guard store.isReady else { waiting = route; return }
        if store.query(route) != nil { path = NavigationPath([route]) }
    }
}

/// The app's shell. On iOS 26 it is Apple's own tab bar in Liquid Glass: the valley, the places you kept, and
/// search as the system's search tab. Before iOS 26 the valley is the whole app, with its own search field.
struct DarbTabs: View {
    @Environment(Store.self) private var store
    @Binding var path: NavigationPath
    @Binding var menu: MenuStart?
    let igniteAt: Date?
    @State private var tab = "home"
    @State private var savedPath = NavigationPath()
    @State private var searchPath = NavigationPath()
    @State private var mapPath = NavigationPath()

    var body: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $tab) {
                Tab(L("דרב"), systemImage: "house.fill", value: "home") { home }
                Tab(L("מפה"), systemImage: "map.fill", value: "map") {
                    NavigationStack(path: $mapPath) {
                        OpenMap { mapPath.append($0) }
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationDestination(for: Route.self) { place($0, in: $mapPath) }
                    }
                }
                Tab(L("שמורים"), systemImage: "bookmark.fill", value: "saved") {
                    NavigationStack(path: $savedPath) {
                        SavedList { savedPath.append(Route.business($0.business.id)) }
                            .background(Color.canvas)
                            .navigationTitle(L("שמורים"))
                            .navigationDestination(for: Route.self) { place($0, in: $savedPath) }
                    }
                }
                Tab(value: "search", role: .search) {
                    NavigationStack(path: $searchPath) {
                        SearchSheet(scope: nil, embedded: true) { searchPath.append(Route.business($0.business.id)) }
                            .navigationDestination(for: Route.self) { place($0, in: $searchPath) }
                    }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tint(Color.ink)
            .sensoryFeedback(.selection, trigger: tab)
            .onAppear { if UserDefaults.standard.string(forKey: "darbTabOpen") == "search" { tab = "search" } else if let t = UserDefaults.standard.string(forKey: "darbTabOpen") { tab = t } }
        } else {
            home
        }
    }

    private var home: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path, menu: $menu, igniteAt: igniteAt)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder private func place(_ r: Route, in stack: Binding<NavigationPath>) -> some View {
        if let q = store.query(r) {
            PlaceView(query: q, flies: false, open: { stack.wrappedValue.append($0) }, plans: { menu = MenuStart(.plans) })
        }
    }
}
