import SwiftUI

/// What Darb knows about a Deluxe partner's look: their colours, and the last copy of their shop (logo, photos).
struct DeluxeLook {
    let source: ShopSource
    let shop: Shop?
    var bg: Color { Color(hex: source.bg) }
    var surface: Color { Color(hex: source.surface) }
    var ink: Color { Color(hex: source.ink) }
    var accent: Color { Color(hex: source.accent) }
    /// What stands on an accent: the pale world's own paper, or Darb's forest on a dark world's gold.
    var onAccent: Color { source.light ? bg : Color(hex: 0x0B2219) }
    var photo: URL? { shop?.heroes.first ?? shop?.items.first(where: { $0.image != nil && $0.tint == nil })?.image }
    /// Whether the shop sells products (a shelf) rather than serving a menu.
    var shelf: Bool { source.system == .shelf }

    @MainActor static func of(_ id: Int, lang: Lang) -> DeluxeLook? {
        guard let s = ShopSource.all[id] else { return nil }
        return DeluxeLook(source: s, shop: ShopLoader.cached(id, lang: ShopLang(lang)))
    }
}

/// The partner's logo on their own colour, ringed in their accent.
struct DeluxeLogo: View {
    let look: DeluxeLook
    var size: CGFloat = 46
    var body: some View { LogoRing(url: look.shop?.logo, bg: look.bg, accent: look.accent, size: size) }
}

/// The small gold doorway that marks a partner whose shop opens inside Darb.
struct DoorBadge: View {
    let accent: Color
    var ink = Color(hex: 0x0B2219)
    var text: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "door.left.hand.open").font(.symbol(size: 11))
            if let text { Text(text).font(.darb(size: 11, .black, relativeTo: .caption2)).lineLimit(1) }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, text == nil ? 6 : 9).frame(height: 22)
        .background(accent, in: Capsule())
    }
}

/// A partner in a list (search, saved): their photo along the card, their logo, name and line on their own colour,
/// and the door into their shop. It takes more room than a plain row, on purpose.
struct DeluxeResultCard: View {
    @Environment(Store.self) private var store
    let entry: Entry
    let look: DeluxeLook
    var body: some View {
        let b = entry.business
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                DeluxeStrip(look: look).frame(height: 120).frame(maxWidth: .infinity).clipped()
                DoorBadge(accent: look.accent, ink: look.onAccent, text: L("חנות בתוך דרב")).padding(10)
            }
            HStack(spacing: 12) {
                DeluxeLogo(look: look, size: 52).offset(y: -18).padding(.bottom, -18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(look.shop?.name ?? b.name).font(.darb(.headline, .black)).lineLimit(1)
                    Text(look.shop?.tagline ?? store.kindName(b.kind)).font(.darb(.caption, .bold)).foregroundStyle(look.accent).lineLimit(1)
                    HStack(spacing: 5) {
                        StatusDot(status: entry.status, size: 6, lit: true)
                        Text(verbatim: "\(entry.status.text) · \(store.placeName(b.place))").font(.darb(.caption)).opacity(0.7).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                VStack(spacing: -2) {
                    Text(verbatim: "\(b.minutes)").font(.figure(.title2, weight: .black)).foregroundStyle(look.accent)
                    Text(L("דק׳")).font(.darb(.caption2, .bold)).opacity(0.7)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
        .foregroundStyle(look.ink)
        .background(look.bg)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(look.accent.opacity(0.55), lineWidth: 1.5) }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("%@, חנות בתוך דרב, %@, %lld דקות", look.shop?.name ?? b.name, entry.status.text, b.minutes))
    }
}

/// On a partner's own page: the doorway into their shop, as a card of their photos with the gold door at its heart.
struct ShopDoorCard: View {
    let look: DeluxeLook
    let name: String
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(spacing: 0) {
                DeluxeStrip(look: look).frame(height: 120).frame(maxWidth: .infinity).clipped()
                HStack(spacing: 16) {
                    // the logo standing in a doorway of their accent: their door, open
                    ZStack {
                        UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 30, style: .continuous)
                            .fill(look.accent)
                            .frame(width: 64, height: 84)
                        LogoRing(url: look.shop?.logo, bg: look.bg, accent: look.bg, size: 50).offset(y: 6)
                    }
                    .offset(y: -32).padding(.bottom, -32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("היכנסו לחנות")).font(.darb(size: 24, .black, relativeTo: .title))
                        Text(look.source.system == .lot ? L("המכוניות של %@, עם תמונות ופרטים, ושאלה בוואטסאפ בלי לצאת מדרב", name)
                             : look.shelf ? L("המוצרים של %@, מחירים ותמונות, והזמנה בלי לצאת מדרב", name) : L("התפריט של %@, מחירים ותמונות, והזמנה בלי לצאת מדרב", name)).font(.darb(.footnote, .semibold)).opacity(0.8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.symbol(.title3)).foregroundStyle(look.accent)
                }
                .foregroundStyle(look.ink)
                .padding(16)
                .background(look.bg)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(look.accent, lineWidth: 2) }
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(PressStyle(scale: 0.98))
    }
}

/// The top of a partner's card: their own photo, or, for a shop of products, the products in front standing side
/// by side, each on its own colour, like a shelf.
struct DeluxeStrip: View {
    let look: DeluxeLook
    var body: some View {
        let jars = Array((look.shop?.windowItems ?? []).filter { $0.tint != nil }.prefix(4))
        if look.photo == nil, !jars.isEmpty {
            HStack(spacing: 0) {
                ForEach(jars) { it in ItemArt(item: it, fill: look.surface, pad: 10) }
            }
            .environment(\.layoutDirection, .leftToRight)
        } else {
            KeptImage(url: look.photo, fill: look.surface) { $0.resizable().scaledToFill() }
        }
    }
}
