import SwiftUI
import UIKit

// A business's own pictures: its logo, its cover, its photos, its storefront.
// No business in the snapshot has given one yet, so today these views are not on screen at all.
// A name starting with "demo:" is not a picture: it is a drawn placeholder for the `-darbDemoMedia`
// testing argument, made of Darb's own 3D objects and shapes, and always marked "הדגמה".

enum Media {
    static func isDemo(_ name: String) -> Bool { name.hasPrefix("demo:") }
    static func image(_ name: String) -> UIImage? { isDemo(name) ? nil : UIImage(named: name) }
}

/// The small "הדגמה" mark on a placeholder.
struct DemoMark: View {
    var body: some View {
        Text(L("הדגמה")).font(.darb(size: 9, .heavy))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(.black.opacity(0.55), in: Capsule())
            .accessibilityLabel(L("תמונת הדגמה"))
    }
}

/// A business's logo.
struct LogoView: View {
    let name: String
    /// The first letter of the business's name, for the placeholder.
    let initial: String
    let tint: Color
    var size: CGFloat = 46

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Group {
            if let image = Media.image(name) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    ColorField(color: tint)
                    Text(initial).font(.darb(size: size * 0.52, .black)).foregroundStyle(Color.onColor)
                }
                .overlay(alignment: .bottom) { if size >= 56 { DemoMark().padding(.bottom, size * 0.05) } }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        // a real logo gets a clean rim; a placeholder gets a dashed one, so it reads as a stand-in even when it is small
        .overlay {
            if Media.isDemo(name) {
                shape.strokeBorder(style: StrokeStyle(lineWidth: max(1.2, size * 0.035), dash: [size * 0.09, size * 0.06])).foregroundStyle(Color.onColor.opacity(0.7))
            } else {
                shape.strokeBorder(.white.opacity(0.75), lineWidth: max(1, size * 0.03))
            }
        }
        .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

/// A cover or a photo, filling whatever frame it is given.
struct PhotoView: View {
    let name: String
    let art: ArtRef
    /// Which placeholder to draw, so three in a row are not the same.
    var variant = 0

    var body: some View {
        if let image = Media.image(name) {
            Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
        } else {
            let tint = Color(hexString: art.tint)
            ZStack {
                ColorField(color: tint.mix(with: variant % 2 == 0 ? .white : Color(hex: 0x3A1E5C), by: 0.08 * Double(variant % 3)))
                GeometryReader { geo in
                    let s = min(geo.size.width, geo.size.height) * [1.25, 0.9, 1.6, 1.1][variant % 4]
                    Group {
                        if let r = art.render { ArtImage(name: r) } else {
                            Image(systemName: art.symbol).resizable().scaledToFit().padding(s * 0.28).foregroundStyle(Color.onColor.opacity(0.3))
                        }
                    }
                    .frame(width: s, height: s)
                    .rotationEffect(.degrees([0, -8, 10, 4][variant % 4]))
                    .position(x: geo.size.width * [0.5, 0.42, 0.62, 0.5][variant % 4], y: geo.size.height * [0.52, 0.5, 0.6, 0.5][variant % 4])
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) { DemoMark().padding(6) }
        }
    }
}

/// How the place looks from the street, to find it on arrival.
struct StorefrontView: View {
    let name: String
    let initial: String
    let tint: Color
    /// Whether a placeholder carries its "הדגמה" mark; off only where the picture is too small to hold it.
    var marked = true

    var body: some View {
        if let image = Media.image(name) {
            Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
        } else {
            // a drawn shopfront: a wall, a striped awning, a door, a window and a sign
            Canvas { g, sz in
                let w = sz.width, h = sz.height
                g.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(tint.mix(with: .white, by: 0.72)))
                g.fill(Path(CGRect(x: 0, y: h * 0.86, width: w, height: h * 0.14)), with: .color(Color.onColor.opacity(0.18)))
                let stripes = 9, top = h * 0.2, drop = h * 0.18
                for i in 0..<stripes {
                    let x = w * 0.1 + CGFloat(i) * w * 0.8 / CGFloat(stripes), sw = w * 0.8 / CGFloat(stripes)
                    var p = Path(CGRect(x: x, y: top, width: sw, height: drop))
                    p.addEllipse(in: CGRect(x: x, y: top + drop - sw / 2, width: sw, height: sw))
                    g.fill(p, with: .color(i % 2 == 0 ? tint : .white))
                }
                g.fill(Path(roundedRect: CGRect(x: w * 0.16, y: h * 0.5, width: w * 0.36, height: h * 0.28), cornerRadius: 4), with: .color(.white.opacity(0.85)))
                g.fill(Path(roundedRect: CGRect(x: w * 0.62, y: h * 0.46, width: w * 0.2, height: h * 0.4), cornerRadius: 4), with: .color(Color.onColor.opacity(0.8)))
                g.fill(Path(roundedRect: CGRect(x: w * 0.3, y: h * 0.05, width: w * 0.4, height: h * 0.12), cornerRadius: 5), with: .color(Color.onColor))
                g.draw(Text(initial).font(.darb(size: h * 0.09, .black)).foregroundStyle(tint), at: CGPoint(x: w * 0.5, y: h * 0.11))
            }
            .environment(\.layoutDirection, .leftToRight)
            .overlay(alignment: .topLeading) { if marked { DemoMark().padding(6) } }
            .clipped()
        }
    }
}
