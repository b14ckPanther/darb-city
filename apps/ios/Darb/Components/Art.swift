import SwiftUI
import UIKit

/// The rendered 3D objects. Each is decoded once, off the main thread, soon after the app opens: at full size for
/// the large pictures, and as a small copy for tiles, rows and the rail, so no picture is ever decoded or scaled
/// down while a list is scrolling.
@MainActor
final class ArtLibrary {
    static let shared = ArtLibrary()
    private var stills: [String: UIImage] = [:]
    private var smalls: [String: UIImage] = [:]
    private var boxes: [String: CGRect] = [:]

    /// A render made ready off the main thread.
    private struct Ready: @unchecked Sendable { let name: String; let full: UIImage; let small: UIImage?; let box: CGRect }

    /// Decodes every render in the bundle in the background, the nine everyday needs first.
    func warm() {
        let first = Need.all.map(\.art)
        Task.detached(priority: .userInitiated) {
            let rest = (Bundle.main.urls(forResourcesWithExtension: "png", subdirectory: nil) ?? [])
                .map { $0.deletingPathExtension().lastPathComponent }.filter { $0.hasPrefix("p-") && !first.contains($0) }.sorted()
            for group in [first, rest] {
                let ready: [Ready] = Perf.time("art.decode") {
                    group.compactMap { name in
                        guard let image = UIImage(named: name) else { return nil }
                        let small = image.preparingThumbnail(of: CGSize(width: 216, height: 216))
                        return Ready(name: name, full: image.preparingForDisplay() ?? image, small: small, box: ArtLibrary.measure(small ?? image))
                    }
                }
                await MainActor.run {
                    for r in ready {
                        ArtLibrary.shared.stills[r.name] = r.full
                        ArtLibrary.shared.smalls[r.name] = r.small
                        ArtLibrary.shared.boxes[r.name] = r.box
                    }
                }
            }
        }
    }

    /// Where the object really is inside its square picture, as a unit rectangle (y runs down).
    /// The renders have empty margins of different sizes, so a shadow has to be placed under the object, not under the picture.
    func box(_ name: String) -> CGRect {
        if let b = boxes[name] { return b }
        let out = still(name).map(ArtLibrary.measure) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        boxes[name] = out
        return out
    }

    private nonisolated static func measure(_ image: UIImage) -> CGRect {
        var out = CGRect(x: 0, y: 0, width: 1, height: 1)
        let n = 96
        if let cg = image.cgImage,
           let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) {
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            if let raw = ctx.data {
                let px = raw.bindMemory(to: UInt8.self, capacity: n * n)
                var minX = n, maxX = -1, minY = n, maxY = -1
                for y in 0..<n { for x in 0..<n where px[y * n + x] > 40 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                } }
                if maxX >= minX {
                    out = CGRect(x: CGFloat(minX) / CGFloat(n), y: CGFloat(minY) / CGFloat(n), width: CGFloat(maxX - minX + 1) / CGFloat(n), height: CGFloat(maxY - minY + 1) / CGFloat(n))
                }
            }
        }
        return out
    }

    func still(_ name: String) -> UIImage? {
        if let i = stills[name] { return i }
        guard !name.isEmpty, let i = UIImage(named: name) else { return nil }
        stills[name] = i
        return i
    }

    /// The small copy, for a picture drawn at the size of a tile or a row.
    func small(_ name: String) -> UIImage? { smalls[name] ?? still(name) }
}

/// A still render of a need's 3D object, or the Darb mark when a kind has none.
struct ArtImage: View {
    let name: String
    /// Drawn at the size of a tile or a row, where the small copy is enough.
    var small = false
    var body: some View {
        if let i = small ? ArtLibrary.shared.small(name) : ArtLibrary.shared.still(name) {
            Image(uiImage: i).resizable().interpolation(.high).antialiased(true).scaledToFit()
        } else {
            Image("Mark").resizable().scaledToFit().padding(8).opacity(0.85)
        }
    }
}

/// A business's picture at small size: its render, or its kind's symbol, on a wash of its colour.
struct ArtThumb: View {
    let art: ArtRef
    var size: CGFloat = 46
    var body: some View {
        if let logo = art.logo {
            LogoView(name: logo, initial: art.initial, tint: Color(hexString: art.tint), size: size)
        } else {
            thumb
        }
    }

    private var thumb: some View {
        Group {
            if let r = art.render {
                // the renders have margins of different sizes, so each is scaled until the object itself fills the tile;
                // the finest ones (the clinic, the sushi, the hummus) get a little more room still
                let box = ArtLibrary.shared.box(r)
                let fill: CGFloat = ArtThumb.fine.contains(r) ? 0.98 : 0.88
                let k = min(1.9, fill / max(box.width, box.height, 0.3))
                ArtImage(name: r, small: size <= 72)
                    .scaleEffect(k)
                    .offset(x: (0.5 - box.midX) * size * k, y: (0.5 - box.midY) * size * k)
                    .environment(\.layoutDirection, .leftToRight)
            } else {
                Image(systemName: art.symbol).font(.symbol(size: size * 0.42)).foregroundStyle(Color.onColor.opacity(0.78))
            }
        }
        .frame(width: size, height: size)
        .background(Color(hexString: art.tint).opacity(art.render == nil ? 0.92 : 0.32), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .accessibilityHidden(true)
    }

    /// Renders whose detail is lost first when they are small.
    static let fine: Set<String> = ["p-clinic", "p-sushi", "p-hummus"]
}

/// A business's picture at full size: the floating render, or its kind's symbol pressed into the field.
struct HeroArt: View {
    let art: ArtRef
    let ink: Color
    var size: CGFloat = 164
    var body: some View {
        if let logo = art.logo {
            LogoView(name: logo, initial: art.initial, tint: Color(hexString: art.tint), size: size * 0.62)
                .frame(width: size, height: size)
        } else if let r = art.render {
            FloatingArt(name: r).frame(width: size, height: size)
        } else {
            // no object of its own: its kind's symbol, on its colour, as its card in the rail shows it
            Image(systemName: art.symbol)
                .font(.symbol(size: size * 0.34))
                .foregroundStyle(Color.onColor.opacity(0.82))
                .frame(width: size * 0.62, height: size * 0.62)
                .background(Color(hexString: art.tint).opacity(0.92), in: Circle())
                .frame(width: size, height: size)
        }
    }
}

/// The 3D object at full resolution, alive without spinning: it rests just above its shadow, rises a point or two
/// as if breathing, and leans with the phone. It is simply there when its card or page arrives; it never pops in.
/// Still under Reduce Motion.
struct FloatingArt: View {
    let name: String
    /// How far it rises, in points. A few at most: the object should read as resting, not hovering.
    var lift: CGFloat = 2.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt = MotionTilt.shared
    /// `-darbStillArt YES` stops the breathing, to measure what it costs.
    private var still: Bool { reduceMotion || UserDefaults.standard.bool(forKey: "darbStillArt") }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let box = ArtLibrary.shared.box(name)
            ZStack {
                // the contact shadow sits right under the object itself: tighter and darker as it comes down
                Ellipse()
                    .fill(.black.opacity(0.26))
                    .frame(width: s * box.width * 0.74, height: s * 0.06)
                    .blur(radius: s * 0.028)
                    .offset(x: (box.midX - 0.5) * s, y: (box.maxY - 0.5) * s + s * 0.012)
                ArtImage(name: name)
                    .phaseAnimator(still ? [false] : [false, true]) { v, up in
                        v.offset(y: up ? -lift : 0)
                    } animation: { _ in .easeInOut(duration: 2.6) }
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : tilt.roll * 10), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : -tilt.pitch * 8), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { if !reduceMotion { tilt.start() } }
        }
        .accessibilityHidden(true)
    }
}
