import SwiftUI

/// The opening: Darb's objects fall from the top one after another and pile up with weight, the mark lands on the
/// pile and the name comes up, then the field folds into the mark's tile in the home screen's header.
/// It is light: nine images moved by springs, nothing drawn frame by frame and nothing blurred. The field follows
/// the app's own look, light or dark.
struct SplashView: View {
    /// The field has begun to fold into the header.
    let closing: Bool
    var skip: () -> Void = {}
    @Environment(\.layoutDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var step = 0

    static let hold = 1.7
    static let fold = Animation.spring(response: 0.44, dampingFraction: 1)
    static let foldTime = 0.44
    static let tile: CGFloat = 44

    /// The pile is the opening; the other two were tried and turned down.
    static let variant = 2

    private var night: Bool { scheme == .dark }
    private var field: Color { night ? Color(hex: 0x051811) : Color(hex: 0xFBF7EC) }
    private var ink: Color { night ? Color(hex: 0xFBF7EC) : .onColor }

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let W = geo.size.width, H = geo.size.height + top + geo.safeAreaInsets.bottom
            let leading = 18 + Self.tile / 2
            let home = CGPoint(x: direction == .rightToLeft ? W - leading : leading, y: top + 4 + Self.tile / 2)
            ZStack {
                RoundedRectangle(cornerRadius: closing ? 14 : 0, style: .continuous)
                    .fill(closing ? Color.onColor : field)
                    .frame(width: closing ? Self.tile : W, height: closing ? Self.tile : H)
                    .position(closing ? home : CGPoint(x: W / 2, y: H / 2))
                if !closing {
                    pile(W: W, H: H)
                        .transition(.opacity)
                }
                if closing || Self.variant != 1 {
                    mark(closing: closing, at: closing ? home : CGPoint(x: W / 2, y: Self.variant == 2 ? H * 0.34 : top + 70))
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .allowsHitTesting(!closing)
        .accessibilityHidden(true)
        .task {
            if reduceMotion { step = 9; return }
            for i in 1...9 {
                try? await Task.sleep(for: .seconds(i == 1 ? 0.05 : 0.17))
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { step = i }
            }
        }
    }

    private func mark(closing: Bool, at p: CGPoint) -> some View {
        let shown = closing || step >= (Self.variant == 2 ? 7 : 1)
        return Image("Mark").resizable().scaledToFit()
            .frame(width: closing ? 25 : 32, height: closing ? 25 : 32)
            .frame(width: closing ? Self.tile : 56, height: closing ? Self.tile : 56)
            .background(Color.onColor, in: RoundedRectangle(cornerRadius: closing ? 14 : 18, style: .continuous))
            .overlay { if !closing { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.mustard.opacity(0.4), lineWidth: 1.5) } }
            .scaleEffect(shown ? 1 : 0.2)
            .opacity(shown ? 1 : 0)
            .position(p)
    }

    // MARK: C, the pile

    private func pile(W: CGFloat, H: CGFloat) -> some View {
        let arts = ["p-crate", "p-bread", "p-coffee", "p-pills", "p-pump", "p-kunafa", "p-plate", "p-coins", "p-garage"]
        // where each one comes to rest: a mound, widest at the bottom
        let rest: [(CGFloat, CGFloat, Double)] = [
            (0.22, 0.70, -12), (0.5, 0.71, 6), (0.78, 0.70, 14),
            (0.36, 0.60, 10), (0.64, 0.60, -8),
            (0.5, 0.50, -4), (0.3, 0.80, 8), (0.7, 0.80, -10), (0.5, 0.81, 0),
        ]
        let order = [8, 6, 7, 0, 1, 2, 3, 4, 5]
        return ZStack {
            ForEach(0..<9, id: \.self) { k in
                let i = order[k]
                let landed = step >= 1 + k * 6 / 9
                ArtImage(name: arts[i], small: true)
                    .frame(width: W * 0.3, height: W * 0.3)
                    .rotationEffect(.degrees(landed ? rest[i].2 : rest[i].2 * 3))
                    .position(x: W * rest[i].0, y: landed ? H * rest[i].1 : -W * 0.3)
            }
            Text(L("דרב")).font(.poster(48)).foregroundStyle(ink)
                .position(x: W / 2, y: H * 0.22)
                .opacity(step >= 7 ? 1 : 0)
        }
    }
}
