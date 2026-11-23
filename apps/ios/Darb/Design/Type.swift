import SwiftUI

// Type. Three faces, one for each language: Heebo for Hebrew, Cairo for Arabic, Ubuntu for English.
// Figures (minutes, prices, counts) are in the same face as the words around them, with tabular digits,
// so a screen is set in one face only. Every size is relative to a text style, so it
// grows with the person's text size. Symbols keep the system's own font, all in one weight.
enum Typeface {
    /// The face's name in the bundle for a language and a weight.
    static func name(_ weight: Font.Weight, in lang: Lang = .current) -> String {
        switch lang {
        case .he: "Heebo-" + step(weight)
        case .ar: "Cairo-" + step(weight)
        // Ubuntu comes in three weights
        case .en: "Ubuntu-" + (weight == .regular || weight == .light ? "Regular" : weight == .medium || weight == .semibold ? "Medium" : "Bold")
        }
    }
    static func figure(_ weight: Font.Weight) -> String { name(weight) }
    private static func step(_ w: Font.Weight) -> String {
        switch w {
        case .medium: "Medium"
        case .semibold: "SemiBold"
        case .bold: "Bold"
        case .heavy: "ExtraBold"
        case .black: "Black"
        default: "Regular"
        }
    }
    /// The point size of a text style at the standard text size.
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
    /// The one weight every symbol is drawn in.
    static let symbolWeight: Font.Weight = .semibold
    /// Every file the app registers, for the test that checks they are all in the bundle.
    static let files: [String] = ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Black"].flatMap { ["Heebo-\($0)", "Cairo-\($0)"] } + ["Ubuntu-Regular", "Ubuntu-Medium", "Ubuntu-Bold", "Karantina-Bold", "Lalezar-Regular", "DSEG7Classic-Bold"]
}

#if canImport(UIKit)
import UIKit

/// A face with the other scripts' faces behind it. Heebo has no Arabic letters and Cairo no Hebrew, so a line of
/// one language holding a word of the other would otherwise fall back to the system's font for that word. Each face
/// carries the other as its fallback, at the same weight, so mixed lines stay in Darb's own type.
enum Cascade {
    nonisolated(unsafe) private static var cache: [String: UIFont] = [:]
    static func font(_ name: String, fallbacks: [String], size: CGFloat, style: Font.TextStyle?) -> Font {
        let key = "\(name)|\(size)|\(String(describing: style))"
        if let f = cache[key] { return Font(f) }
        let list = fallbacks.map { UIFontDescriptor(fontAttributes: [.name: $0]) }
        let desc = UIFontDescriptor(fontAttributes: [.name: name]).addingAttributes([.cascadeList: list])
        var ui = UIFont(descriptor: desc, size: size)
        if let style { ui = UIFontMetrics(forTextStyle: style.uiStyle).scaledFont(for: ui) }
        cache[key] = ui
        return Font(ui)
    }
}

private extension Font.TextStyle {
    var uiStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
}
#endif

extension Font {
    /// The language's face, with the other script's face behind it for any word written in it.
    private static func face(_ weight: Font.Weight, size: CGFloat, style: Font.TextStyle?, lang: Lang = .current) -> Font {
        let main = Typeface.name(weight, in: lang)
        let he = Typeface.name(weight, in: .he), ar = Typeface.name(weight, in: .ar)
        let others = [he, ar].filter { $0 != main }
        return Cascade.font(main, fallbacks: others, size: size, style: style)
    }

    /// Text in the language's own face, at a text style's size.
    static func darb(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        face(style == .headline && weight == .regular ? .semibold : weight, size: Typeface.size(style), style: style)
    }
    /// Text in the language's own face, at a size of its own that still grows with the text size.
    static func darb(size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        face(weight, size: size, style: style)
    }
    /// Text in one language's face whatever language is in use: a language's own name, for one.
    static func darb(_ style: Font.TextStyle, _ weight: Font.Weight = .regular, in lang: Lang) -> Font {
        face(weight, size: Typeface.size(style), style: style, lang: lang)
    }
    /// Figures: the language's own face, with tabular digits.
    static func figure(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        face(weight, size: Typeface.size(style), style: style).monospacedDigit()
    }
    static func figure(size: CGFloat, _ weight: Font.Weight = .bold, relativeTo style: Font.TextStyle = .title) -> Font {
        face(weight, size: size, style: style).monospacedDigit()
    }
    /// The poster face: tall, condensed, loud, like a painted shop sign. Karantina for Hebrew and Latin, Lalezar for
    /// Arabic. Used for names of needs and titles only; reading text stays in the language's own face.
    static func poster(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        Lang.current == .ar
            ? Cascade.font("Lalezar-Regular", fallbacks: ["Karantina-Bold", "Heebo-Black"], size: size * 0.74, style: style)
            : Cascade.font("Karantina-Bold", fallbacks: ["Lalezar-Regular", "Cairo-Black"], size: size, style: style)
    }
    /// The sign face: seven segment digits, like the lit "open" sign over a shop door. Minutes and hours only.
    static func lcd(_ size: CGFloat) -> Font { .custom("DSEG7Classic-Bold", fixedSize: size) }
    /// A symbol at a text style's size, in the one symbol weight.
    static func symbol(_ style: Font.TextStyle) -> Font { .system(style).weight(Typeface.symbolWeight) }
    static func symbol(size: CGFloat) -> Font { .system(size: size, weight: Typeface.symbolWeight) }
}

extension View {
    /// Display type: heavy, for names and titles.
    func display(_ size: CGFloat, weight: Font.Weight = .heavy, relativeTo: Font.TextStyle = .largeTitle) -> some View {
        font(.darb(size: size, weight, relativeTo: relativeTo))
    }
    /// Figures: tabular, for minutes, prices and counts.
    func figure(_ size: CGFloat, weight: Font.Weight = .bold, relativeTo: Font.TextStyle = .title) -> some View {
        font(.figure(size: size, weight, relativeTo: relativeTo))
    }
    /// The small label above a block.
    func eyebrow() -> some View { font(.darb(.caption, .bold)).kerning(Lang.current == .en ? 0.4 : 0) }
}
