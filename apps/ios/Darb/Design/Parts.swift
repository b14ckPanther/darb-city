import SwiftUI

// The small parts every sheet and page is built from, so they all look like one app.

/// Darb's menu sign: two bars, the lower one shorter, like a path that sets off. Drawn, not a system symbol.
struct MenuGlyph: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule().frame(width: 19, height: 2.6)
            Capsule().frame(width: 12, height: 2.6)
        }
        .accessibilityHidden(true)
    }
}

/// The round close button of a sheet.
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.symbol(.footnote))
                .frame(width: 32, height: 32).background(Color.card2, in: Circle())
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(L("סגירה"))
    }
}

/// A symbol on a small tile: how every row in the app carries its icon.
struct IconTile: View {
    let symbol: String
    var tint: Color = .card2
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: symbol).font(.symbol(size: size * 0.42))
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A group of rows on one raised card, with hairlines between them.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row
                    if row.id != rows.last?.id { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1).padding(.leading, 46) }
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: Radius.tile)
    }
}

/// One row: an icon tile, a title, maybe a line under it, maybe a value, and what tapping it does.
struct MenuRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var tint: Color = .card2
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.darb(.subheadline, .bold)).multilineTextAlignment(.leading)
                if let detail { Text(detail).font(.darb(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: 6)
            trailing
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

extension MenuRow where Trailing == RowChevron {
    init(symbol: String, title: String, detail: String? = nil, tint: Color = .card2) {
        self.init(symbol: symbol, title: title, detail: detail, tint: tint) { RowChevron() }
    }
}

struct RowChevron: View {
    var body: some View { Image(systemName: "chevron.forward").font(.symbol(.caption)).foregroundStyle(.tertiary).accessibilityHidden(true) }
}

/// The small heading above a group.
struct GroupTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.darb(.caption, .bold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6).padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A choice among a few, as one capsule with a pill that moves to the chosen one.
struct Segments<Value: Hashable>: View {
    let options: [(value: Value, title: String, font: Font?)]
    @Binding var selection: Value
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { o in
                let on = o.value == selection
                Button { withAnimation(reduceMotion ? nil : Motion.select) { selection = o.value }; Haptic.tap() } label: {
                    Text(o.title).font(o.font ?? .darb(.subheadline, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .foregroundStyle(on ? Color.canvas : Color.ink.opacity(0.65))
                        .background { if on { Capsule().fill(Color.ink).matchedGeometryEffect(id: "pill", in: ns) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.card2, in: Capsule())
    }
}

/// The main button of a page.
struct MainButtonStyle: ButtonStyle {
    var busy = false
    var quiet = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.darb(.headline, .heavy))
            .frame(maxWidth: .infinity).frame(height: 54)
            .foregroundStyle(quiet ? Color.ink : Color.canvas)
            .background(quiet ? AnyShapeStyle(Color.card2) : AnyShapeStyle(Color.ink), in: Capsule())
            .opacity(busy ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.9), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// A labelled field of a form, with its hint or its error under it.
struct Field<Content: View>: View {
    let label: String
    var optional = false
    var hint: String? = nil
    var error: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).font(.darb(.footnote, .bold))
                if optional { Text(L("web.contact.form.optional")).font(.darb(.caption)).foregroundStyle(.secondary) }
            }
            content
                .font(.darb(.body))
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(error == nil ? Color.ink.opacity(0.1) : Color.shut, lineWidth: error == nil ? 1 : 1.5) }
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill").font(.darb(.caption, .semibold)).foregroundStyle(Color.shut)
            } else if let hint {
                Text(hint).font(.darb(.caption)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The frame every page inside a sheet shares: paper or ink behind, the app's ink for text.
struct PageChrome: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        content
            .background(Color.canvas)
            .foregroundStyle(Color.ink)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.canvas, for: .navigationBar)
    }
}

extension View {
    func page(_ title: String) -> some View { modifier(PageChrome(title: title)) }
}

/// A message that takes the place of a page's content: nothing here yet, or something went wrong.
struct Notice: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var body: some View {
        VStack(spacing: 8) {
            IconTile(symbol: symbol, size: 52)
            Text(title).font(.darb(.headline, .bold)).multilineTextAlignment(.center)
            if let message { Text(message).font(.darb(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .padding(.horizontal, 24).padding(.vertical, 30)
        .frame(maxWidth: .infinity)
    }
}
