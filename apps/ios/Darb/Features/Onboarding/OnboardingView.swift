import SwiftUI

/// The first run, in three short steps and taps only: what Darb is and in which language,
/// what it answers, and where the person is. Any step can be skipped.
/// What Darb says about itself here is the website's own copy (apps/web/src/content/landing.ts).
struct OnboardingView: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let finish: () -> Void
    @State private var step = UserDefaults.standard.integer(forKey: "darbOnboardStep")
    @State private var showTowns = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(Color.ink.opacity(i == step ? 1 : 0.18)).frame(width: i == step ? 22 : 7, height: 7)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(L("שלב %lld מתוך %lld", step + 1, 3))
                Spacer()
                Button(action: finish) {
                    Text(L("דילוג")).font(.darb(.subheadline, .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 20).padding(.top, 6)
            ZStack {
                switch step {
                case 0: hello.transition(.opacity)
                case 1: answers.transition(.opacity)
                default: whereStep.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.canvas.ignoresSafeArea())
        .foregroundStyle(Color.ink)
        // whatever the person chose there, the app is ready
        .sheet(isPresented: $showTowns, onDismiss: finish) { TownChooser() }
        .onChange(of: store.location.access) { old, new in
            // the person answered the system's question, either way
            if step == 2, old == .unasked, new == .allowed { finish() }
        }
    }

    private func next() {
        Haptic.tap()
        withAnimation(reduceMotion ? nil : Motion.land) { step += 1 }
    }

    // MARK: what Darb is, and the language

    private var hello: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            // three of the everyday needs, as the objects they are in the app, each on the light of its own colour
            GeometryReader { geo in
                // sized to the screen, so the three always stand side by side inside it
                let w = min(geo.size.width, 400)
                HStack(alignment: .center, spacing: -w * 0.07) {
                    lit("p-pump", 0x5AA8FF, w * 0.33)
                    lit("p-plate", 0xFF7A59, w * 0.48).zIndex(1)
                    lit("p-pills", 0x3DDC97, w * 0.33)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(height: 210)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Image("Mark").resizable().scaledToFit().frame(width: 22, height: 22)
                    .frame(width: 40, height: 40)
                    .background(Color.onColor, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(L("דרב")).font(.darb(.title3, .black))
            }
            .accessibilityElement(children: .combine)
            Text(verbatim: L("web.landing.hero.title") + "\n" + L("web.landing.hero.accent")).display(40).lineSpacing(-4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            Text(L("web.landing.hero.lead")).font(.darb(.body)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            LanguageSwitch().padding(.top, 22)
            Button(action: next) { Text(L("המשך")) }
                .buttonStyle(MainButtonStyle())
                .padding(.top, 12)
        }
        .padding(.horizontal, 22).padding(.bottom, 18)
    }

    private func lit(_ art: String, _ hex: UInt32, _ size: CGFloat) -> some View {
        FloatingArt(name: art, lift: 3)
            .frame(width: size, height: size)
            .background { Circle().fill(Color.mustard).frame(width: size * 0.92, height: size * 0.92) }
    }

    // MARK: what it answers

    private var answers: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(L("מה דרב עונה")).display(34)
            VStack(alignment: .leading, spacing: 10) {
                fact("p-coffee", 0xE0A571, L("פתוח, והכי קרוב"), L("לכל צורך יומיומי, המקום הפתוח הקרוב ביותר, כמה דקות נסיעה ועד מתי."))
                fact("p-falafel", 0xFF7A59, L("web.landing.platform.layers.2.title"), L("web.landing.platform.layers.2.body"))
                fact("p-garage", 0xAEBBD8, L("web.landing.platform.layers.3.title"), L("web.landing.platform.layers.3.body"))
            }
            .padding(.top, 18)
            Spacer(minLength: 0)
            Text(L("עסקים אמיתיים בלבד, ממקורות ציבוריים.")).font(.darb(.footnote)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: next) { Text(L("המשך")) }
                .buttonStyle(MainButtonStyle())
                .padding(.top, 14)
        }
        .padding(.horizontal, 22).padding(.bottom, 18)
    }

    private func fact(_ art: String, _ hex: UInt32, _ title: String, _ body: String) -> some View {
        HStack(spacing: 14) {
            ArtImage(name: art).frame(width: 62, height: 62)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.darb(.headline, .heavy)).fixedSize(horizontal: false, vertical: true)
                Text(body).font(.darb(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: Radius.tile)
        .accessibilityElement(children: .combine)
    }

    // MARK: where the person is

    private var whereStep: some View {
        let denied = store.location.access == .denied
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Image(systemName: "location.fill").font(.symbol(size: 30))
                .frame(width: 76, height: 76)
                .foregroundStyle(Color.onColor)
                .background(ColorField(color: .mustard).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
                .accessibilityHidden(true)
            Text(L("איפה אתם?")).display(36).padding(.top, 18)
            Text(denied ? L("web.near.denied") : L("web.near.ask")).font(.darb(.body)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Text(L("המיקום משמש רק במכשיר, כדי למדוד מה קרוב. אפשר גם לבחור ישוב, ולשנות בכל רגע.")).font(.darb(.footnote)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 0)
            if !denied {
                Button {
                    Haptic.tap()
                    store.followLocation()
                    if store.location.access == .allowed { finish() }
                } label: { Label(L("web.near.useMyLocation"), systemImage: "location.fill") }
                    .buttonStyle(MainButtonStyle())
            }
            Button { showTowns = true } label: { Text(L("לבחור ישוב")) }
                .buttonStyle(MainButtonStyle(quiet: !denied))
                .padding(.top, 10)
        }
        .padding(.horizontal, 22).padding(.bottom, 18)
    }
}
