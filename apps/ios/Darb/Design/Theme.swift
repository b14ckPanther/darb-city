import SwiftUI
import UIKit

// Darb's look in one place.
//
// The world follows the hour, not the phone's setting: by day the app is warm paper under a Galilee sky,
// by night it is ink with lit windows. A need's colour is the only strong colour, and it is used as a light:
// a field behind the place you are looking at, a glow behind an object. Everything else is ink and paper.

extension Color {
    /// Surfaces, each with a day and a night value in the asset catalog.
    static let canvas = Color("Canvas")
    static let sheet = Color("Sheet")
    static let card = Color("Card")
    static let card2 = Color("Card2")
    /// The text colour: deep ink by day, warm white by night.
    static let ink = Color("Ink")
    static let open = Color("Open")
    static let soon = Color("Soon")
    static let appt = Color("Appt")
    static let shut = Color("Closed")
    /// Ink for text that sits on a need's colour, the same by day and by night: Darb's forest.
    static let onColor = Color(hex: 0x0B2219)
    /// Darb's mustard: the brand's one loud colour, also the light of a lit window.
    static let lamp = Color(hex: 0xFFC330)
    static let mustard = Color(hex: 0xFFC330)
    /// Darb's forest, for solid dark fields.
    static let forest = Color(hex: 0x0E3527)
    /// Darb's own gold, deep enough to read on paper.
    static let gold = Color(hex: 0xB8862E)
}

extension Status {
    var color: Color {
        switch state {
        case .open: .open
        case .closingSoon: .soon
        case .appointment: .appt
        case .closed: .shut
        }
    }
    /// The same four states for use on a coloured or dark field, where the asset colours would lose contrast.
    var lit: Color {
        switch state {
        case .open: Color(hex: 0x3DDC97)
        case .closingSoon: Color(hex: 0xFFB547)
        case .appointment: Color(hex: 0xB9A8FF)
        case .closed: Color(hex: 0x9AA0BC)
        }
    }
}

// MARK: type

/// Corner radii: a stage, a card, a control.
enum Radius {
    static let stage: CGFloat = 34
    static let card: CGFloat = 26
    static let tile: CGFloat = 22
    static let control: CGFloat = 16
}

// MARK: surfaces

/// A surface: one flat colour and a hairline edge. No glow, no fade, no soft shadow.
struct Surface: ViewModifier {
    var radius: CGFloat = Radius.card
    var fill: Color = .card

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            shape.fill(fill).overlay { shape.strokeBorder(Color.ink.opacity(0.1), lineWidth: 1) }
        }
    }
}

extension View {
    func surface(radius: CGFloat = Radius.card, fill: Color = .card) -> some View {
        modifier(Surface(radius: radius, fill: fill))
    }
}

/// A need's colour as a field: one flat, solid colour.
struct ColorField: View {
    let color: Color
    var body: some View { Rectangle().fill(color) }
}

// MARK: small parts

/// A small light for open, closing soon, by appointment or closed. An open one has a halo.
struct StatusDot: View {
    let status: Status
    var size: CGFloat = 7
    /// Use the brighter colours, for a dark or coloured field.
    var lit = false
    var body: some View {
        let c = lit ? status.lit : status.color
        Circle().fill(c).frame(width: size, height: size)
            .background { if status.isOpen { Circle().fill(c.opacity(0.3)).frame(width: size * 2.1, height: size * 2.1) } }
            .accessibilityHidden(true)
    }
}

/// The label on a paid or advertising placement.
struct PaidTag: View {
    let text: String
    var body: some View {
        Text(text).font(.darb(.caption2, .bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.primary.opacity(0.1), in: Capsule())
            .fixedSize()
    }
}

/// The press that every tappable card shares: it sinks a little and springs back.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

extension EnvironmentValues {
    /// The tile around this view is being touched: its object lifts towards the finger.
    @Entry var tilePressed = false
}

/// A tile answers the touch itself, before the finger lifts: it gives a little, its object rises to meet the
/// finger, and the phone ticks once. Letting go springs it back with a small overshoot.
struct TileStyle: ButtonStyle {
    var scale: CGFloat = 0.955
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.tilePressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? scale : 1)
            // letting go settles back with no overshoot: the page that opens grows from the tile at its true size
            .animation(configuration.isPressed ? .spring(response: 0.16, dampingFraction: 0.9) : .spring(response: 0.22, dampingFraction: 1), value: configuration.isPressed)
            .sensoryFeedback(trigger: configuration.isPressed) { _, down in down ? .impact(weight: .light, intensity: 0.75) : nil }
    }
}

/// Darb's sticker: a flat fill, a thick forest outline, and a hard shadow straight down, like a sticker on paper.
/// The outline is what lets loud colours sit side by side and still belong together.
struct Sticker: ViewModifier {
    var fill: Color
    var radius: CGFloat = 22
    var line: CGFloat = 3
    var drop: CGFloat = 4
    var pressed = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background { shape.fill(fill) }
            .overlay { shape.strokeBorder(Color.onColor, lineWidth: line) }
            .background { shape.fill(Color.onColor).offset(y: pressed ? 1 : drop) }
            .offset(y: pressed ? drop - 1 : 0)
    }
}

extension View {
    func sticker(_ fill: Color, radius: CGFloat = 22, line: CGFloat = 3, drop: CGFloat = 4, pressed: Bool = false) -> some View {
        modifier(Sticker(fill: fill, radius: radius, line: line, drop: drop, pressed: pressed))
    }
}

/// A lit seven segment sign: the digits glow mustard on a forest plate, with the unlit segments faintly behind,
/// the way a real shop's LED sign looks. Closed signs go dark.
struct SignDigits: View {
    let text: String
    var size: CGFloat = 20
    var lit = true
    var body: some View {
        let ghost = String(text.map { $0.isNumber ? "8" : $0 })
        ZStack(alignment: .trailing) {
            Text(verbatim: ghost).font(.lcd(size)).foregroundStyle(Color.mustard.opacity(0.13))
            Text(verbatim: text).font(.lcd(size)).foregroundStyle(lit ? Color.mustard : Color(hex: 0x6F8A7D))
                .contentTransition(.numericText())
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, size * 0.32).padding(.vertical, size * 0.24)
        .background(Color.onColor, in: RoundedRectangle(cornerRadius: size * 0.36, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A small square control on the valley, in Apple's Liquid Glass where the phone has it.
struct GlassTile: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape).contentShape(shape)
        } else {
            content.background(Color.ink.opacity(0.08), in: shape).contentShape(shape)
        }
    }
}

/// A round control that floats over a picture or a coloured field.
struct GlassCircle: ViewModifier {
    var size: CGFloat = 44
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.frame(width: size, height: size).glassEffect(.regular.interactive(), in: .circle)
        } else {
            content.frame(width: size, height: size).background(.ultraThinMaterial, in: Circle())
        }
    }
}

extension View {
    func glassCircle(_ size: CGFloat = 44) -> some View { modifier(GlassCircle(size: size)) }

    /// Content that waits for its page to arrive, then appears with a short fade and a small rise.
    func lands(_ on: Bool, reduceMotion: Bool = false) -> some View {
        opacity(on ? 1 : 0).offset(y: on || reduceMotion ? 0 : Motion.rise)
    }
}

// Motion, by three rules.
// One thing moves at a time: a card grows into its page first, and only then does the page's content appear.
// Nothing passes behind or through anything else: content changes where it stands, with a fade and a small rise.
// Nothing bounces: every spring is critically damped, and every move is over in well under half a second.
enum Motion {
    /// Selection: a highlight sliding to its new place.
    static let select = Animation.spring(response: 0.32, dampingFraction: 1)
    /// Content changing where it stands.
    static let swap = Animation.easeOut(duration: 0.22)
    /// A page's content appearing once the page itself has arrived.
    static let land = Animation.easeOut(duration: 0.18)
    /// How long a tile takes to grow into its page: the content waits this long.
    static let flight = 0.3
    /// How long the page's content takes to land.
    static let landTime = 0.18
    /// The still moment between the page landing and its stage turning from the need to the place.
    static let hold = 0.06
    /// The stage turning from the need's title card to the place, where it stands: a plain crossfade.
    static let resolve = Animation.easeInOut(duration: 0.2)
    /// How long a page's content takes to leave before the page shrinks back into its tile.
    static let leave = 0.14
    /// How far content rises as it appears.
    static let rise: CGFloat = 8
}

enum Haptic {
    @MainActor static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    @MainActor static func done() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
