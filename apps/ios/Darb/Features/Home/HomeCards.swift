import SwiftUI

/// A soft bar where a line of text will be, for the moment before the data is in.
struct Skeleton: View {
    var width: CGFloat
    var height: CGFloat = 10
    var body: some View { Capsule().fill(Color.primary.opacity(0.1)).frame(width: width, height: height).accessibilityHidden(true) }
}

/// The lead card: one need, answered with the nearest place open now, as the biggest sticker on the sheet.
/// The need's name and the reason are drawn over it by the home screen, as a menu.
struct LeadCard: View {
    @Environment(Store.self) private var store
    @Environment(\.tilePressed) private var pressed
    let need: Need
    let entry: Entry?
    let height: CGFloat
    var loading = false
    var line: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                // the top band is left for the switch
                Color.clear.frame(height: 40)
                if let e = entry {
                    Text(e.business.name).font(.poster(30, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    HStack(alignment: .center, spacing: 8) {
                        SignDigits(text: String(format: "%02d", min(99, e.business.minutes)), size: 22, lit: e.status.isOpen)
                        Text(L("דק׳")).font(.darb(.footnote, .heavy))
                        Text(line ?? e.status.text).font(.darb(.caption, .heavy)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                } else if loading {
                    Skeleton(width: 140, height: 18)
                    Spacer(minLength: 0)
                    Skeleton(width: 170, height: 26).padding(.bottom, 4)
                } else {
                    Text(L("אין במרחק נסיעה")).font(.poster(26, relativeTo: .title2)).opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: height * 0.78)
        }
        .foregroundStyle(Color.onColor)
        .padding(.leading, 16).padding(.trailing, 8).padding(.top, 6).padding(.bottom, 12)
        .frame(height: height)
        .sticker(need.color, radius: Radius.card, pressed: pressed)
        .overlay(alignment: .topTrailing) {
            // the answer's own object, big enough to break out of the card's top edge
            let art = store.answerArt(need, entry)
            FloatingArt(name: art)
                .frame(width: height * 0.66, height: height * 0.66)
                .modifier(Hop(pressed: pressed))
                .padding(.trailing, 12).padding(.top, 8).offset(y: pressed ? 3 : 0)
                .id(art)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.map { L("%@: %@, %lld דקות, %@", need.title, $0.business.name, $0.business.minutes, $0.status.text) } ?? need.title)
        .accessibilityHint(L("פותח את כל המקומות מהסוג הזה"))
    }
}

/// A need as a sticker: its name painted large and its object, nothing else. What is nearest and how far is on
/// the need's own page. The object sits fully inside the tile, so the zoom into the page never cuts it.
struct NeedTile: View {
    @Environment(Store.self) private var store
    @Environment(\.tilePressed) private var pressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let need: Need
    let entry: Entry?
    var loading = false

    var body: some View {
        let pulse = store.pulse(need)
        let quiet = store.isReady && pulse.open == 0
        ZStack(alignment: .topLeading) {
            Text(need.short).font(.poster(30, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.55)
                .padding(.leading, 12).padding(.trailing, 58).padding(.top, 9)
            ArtImage(name: need.art, small: true)
                .frame(width: 64, height: 64)
                .saturation(quiet ? 0.2 : 1)
                .shadow(color: .black.opacity(0.22), radius: 2, y: 3)
                .modifier(Hop(pressed: pressed))
                .rotationEffect(.degrees(-5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 6).padding(.bottom, 6)
                .offset(y: pressed ? 3 : 0)
                .accessibilityHidden(true)
            // what is alive in this need right now: how many are open, on a lit sign in the free corner,
            // and how late the night runs, on a small tag at the foot
            if store.isReady {
                HStack(spacing: 4) {
                    Circle().fill(quiet ? Color("Closed") : Color(hex: 0x2FCF86)).frame(width: 7, height: 7)
                        .phaseAnimator(quiet || reduceMotion ? [false] : [false, true]) { v, on in v.opacity(on ? 0.35 : 1) } animation: { _ in .easeInOut(duration: 0.9) }
                    SignDigits(text: "\(min(999, pulse.open))", size: 12, lit: !quiet)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 9).padding(.top, 13)
                Text(quiet ? L("הכל סגור") : pulse.latest.map { L("עד %@", OpenHours.clock($0)) } ?? L("פתוחים"))
                    .font(.darb(size: 10, .black, relativeTo: .caption2)).monospacedDigit().lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .sticker(Color(hex: 0xFBF7EC), radius: 6, line: 1.5, drop: 1.5)
                    .rotationEffect(.degrees(-4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, 9).padding(.bottom, 12)
                    .offset(y: pressed ? 3 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.onColor)
        .sticker(quiet ? Color(hex: 0xE4DDD0) : need.color, radius: Radius.tile, pressed: pressed)
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("%@: %lld פתוחים", need.title, pulse.open))
        .accessibilityHint(L("פותח את כל המקומות מהסוג הזה"))
    }
}

/// The ninth tile: every other kind of business.
struct EverythingTile: View {
    @Environment(\.tilePressed) private var pressed
    let kinds: Int
    let places: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("כל השאר")).font(.poster(28, relativeTo: .title2)).lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 4) {
                SignDigits(text: "\(min(999, kinds))", size: 15)
                Text(L("סוגים")).font(.darb(.caption2, .heavy))
            }
            Text(L("%lld מקומות", places)).font(.darb(.caption2, .bold)).monospacedDigit().opacity(0.7).padding(.top, 4)
        }
        .padding(.horizontal, 11).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.onColor)
        .sticker(Color(hex: 0xFBF7EC), radius: Radius.tile, pressed: pressed)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "square.grid.2x2.fill").font(.symbol(size: 26))
                .foregroundStyle(Color.onColor)
                .symbolEffect(.wiggle.byLayer, options: .repeat(.periodic(delay: 4)))
                .rotationEffect(.degrees(-6))
                .padding(.top, 10).padding(.trailing, 10)
                .accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityHint(L("כל סוגי העסקים באזור"))
    }
}

/// The ticker between the valley and the needs, running like a departure board: the towns around and how many are
/// open in each. It is a slot of its own, so a paid line can run in it later, marked as one, between the towns.
struct TownTicker: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    /// Points a second.
    private let speed: Double = 32

    var body: some View {
        let items = store.townStats.prefix(12).map { (name: store.placeName($0.slug), open: $0.open) }
        // drawn, not laid out: one canvas a frame, so running it costs next to nothing and never disturbs the screen
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { ctx in
            Canvas(rendersAsynchronously: true) { g, size in
                let ivory = Color(hex: 0xFBF7EC), mustard = Color.mustard
                var cells: [(GraphicsContext.ResolvedText, GraphicsContext.ResolvedText, CGFloat, CGFloat)] = []
                var total: CGFloat = 0
                for it in items {
                    let n = g.resolve(Text(it.name).font(.poster(22)).foregroundColor(ivory))
                    let c = g.resolve(Text(verbatim: "\(it.open)").font(.lcd(12)).foregroundColor(mustard))
                    let nw = n.measure(in: size).width, cw = c.measure(in: size).width
                    cells.append((n, c, nw, cw))
                    total += nw + 6 + cw + 30
                }
                guard total > 0 else { return }
                let shift = CGFloat((ctx.date.timeIntervalSince(start) * speed).truncatingRemainder(dividingBy: Double(total)))
                var x = -shift
                let y = size.height / 2
                while x < size.width {
                    for (n, c, nw, cw) in cells {
                        if x + nw + cw + 40 > 0 && x < size.width {
                            g.draw(n, at: CGPoint(x: x, y: y), anchor: .leading)
                            g.draw(c, at: CGPoint(x: x + nw + 6, y: y), anchor: .leading)
                            g.fill(Path(ellipseIn: CGRect(x: x + nw + 6 + cw + 12, y: y - 2.5, width: 5, height: 5)), with: .color(mustard.opacity(0.7)))
                        }
                        x += nw + 6 + cw + 30
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: 34)
        .background(Color.onColor)
        .accessibilityHidden(true)
    }
}

/// The object's answer to a touch: it crouches as the finger lands, then hops when the finger lifts, like
/// something alive. Plays as a keyframe animation so the hop has weight: up fast, a slight hang, and a soft landing.
struct Hop: ViewModifier {
    let pressed: Bool
    var hopsOnRelease = false
    @State private var hops = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: pressed ? 1.12 : 1, y: pressed ? 0.88 : 1, anchor: .bottom)
            .animation(.spring(response: 0.18, dampingFraction: 1), value: pressed)
            .keyframeAnimator(initialValue: HopFrame(), trigger: hops) { v, f in
                v.offset(y: f.y).rotationEffect(.degrees(f.tilt)).scaleEffect(f.scale, anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack(\.y) {
                    SpringKeyframe(-14, duration: 0.16, spring: .snappy)
                    SpringKeyframe(0, duration: 0.32, spring: .bouncy(duration: 0.32, extraBounce: 0.1))
                }
                KeyframeTrack(\.tilt) {
                    CubicKeyframe(-7, duration: 0.14)
                    CubicKeyframe(4, duration: 0.14)
                    CubicKeyframe(0, duration: 0.2)
                }
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.08, duration: 0.16)
                    CubicKeyframe(1, duration: 0.3)
                }
            }
            // the hop is kept for things that stay on screen; a tile that opens a page only squashes, so the page
            // grows from it as it is
            .onChange(of: pressed) { _, down in if !down, !reduceMotion, hopsOnRelease { hops += 1 } }
    }
}

struct HopFrame {
    var y: CGFloat = 0
    var tilt: Double = 0
    var scale: CGFloat = 1
}

/// A paid placement on the home screen: a business on a paid plan, always labelled, and apart from the honest answer.
struct SponsorCard: View {
    @Environment(Store.self) private var store
    let sponsorship: Sponsorship
    let entry: Entry
    let compact: Bool

    var body: some View {
        let b = entry.business
        HStack(spacing: 10) {
            ArtThumb(art: store.art(for: b), size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(b.name).font(.darb(.subheadline, .bold)).lineLimit(1)
                HStack(spacing: 5) {
                    StatusDot(status: entry.status, size: 6)
                    Text(verbatim: "\(entry.status.text) · " + L("%lld דק׳", b.minutes)).font(.darb(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            PaidTag(text: sponsorship.demo ? L("ממומן · הדגמה") : L("ממומן"))
            Image(systemName: "chevron.forward").font(.symbol(.caption)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: compact ? 52 : 56)
        .background(Color.lamp.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.lamp.opacity(0.75), lineWidth: 1.2) }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("ממומן. %@, %@, %lld דקות", b.name, entry.status.text, b.minutes))
    }
}

/// The paid placement while nobody has bought it: Darb's own card, inviting a business to appear here.
struct HouseSponsorCard: View {
    let from: Int?
    let compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Darb's own card carries Darb's own mark
            Image("Mark").resizable().scaledToFit().frame(width: 22, height: 22)
                .frame(width: 40, height: 40)
                .background(Color.onColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(L("כאן יכול להופיע העסק שלכם")).font(.darb(.subheadline, .bold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(from.map { L("מקום בולט בדרב, מ ₪%lld לחודש", $0) } ?? L("מקום בולט בדרב")).font(.darb(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            PaidTag(text: L("ממומן"))
            Image(systemName: "chevron.forward").font(.symbol(.caption)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: compact ? 52 : 56)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(.primary.opacity(0.22))
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("ממומן. כאן יכול להופיע העסק שלכם. פותח את התוכניות של דרב"))
    }
}
