import CoreImage.CIFilterBuiltins
import SwiftUI

/// The visitor's Darb card: its QR for the counter to scan, its code to read out, and the stamps at each partner.
/// No name, no email: the card is this phone's.
struct MyCardView: View {
    @State private var card: LoyaltyCard?
    @State private var failed = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let card {
                    pass(card)
                    if card.standings.isEmpty {
                        Text(L("עוד אין הטבות פעילות. כשעסק יצטרף, ההטבה שלו תופיע כאן."))
                            .font(.darb(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    } else {
                        ForEach(card.standings) { StandingCard(standing: $0) }
                    }
                } else if failed {
                    ContentUnavailableView(L("אין חיבור"), systemImage: "wifi.slash", description: Text(L("הכרטיס יופיע כשיהיה חיבור.")))
                        .font(.darb(.body))
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .padding(16)
        }
        .background(Color.canvas)
        .page(L("כרטיס דרב"))
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: phase) { _, p in if p == .active { Task { await load() } } }
    }

    private func load() async {
        do { card = try await LoyaltyAPI.myCard(); failed = false }
        catch { if card == nil { failed = true } }
    }

    /// The card itself: forest, the mark, the QR on an ivory plate, and the code in groups of five.
    private func pass(_ card: LoyaltyCard) -> some View {
        VStack(spacing: 14) {
            HStack {
                Image("Mark").resizable().scaledToFit().frame(width: 26, height: 26)
                Text(L("דרב")).font(.poster(30))
                Spacer()
                Text(L("כרטיס מועדון")).font(.darb(.caption, .heavy)).opacity(0.75)
            }
            QRCode(text: LoyaltyAPI.scanURL(card.code).absoluteString)
                .frame(width: 210, height: 210)
                .padding(14)
                .background(Color(hex: 0xFBF7EC), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityLabel(L("קוד QR של הכרטיס"))
            Text(verbatim: "\(card.code.prefix(5)) \(card.code.suffix(5))")
                .font(.system(size: 24, weight: .heavy, design: .monospaced)).foregroundStyle(Color.mustard)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(card.code.map(String.init).joined(separator: " "))
            Text(L("מראים את הכרטיס בקופה, והצוות סורק אותו."))
                .font(.darb(.footnote, .semibold)).opacity(0.8).multilineTextAlignment(.center)
        }
        .foregroundStyle(Color(hex: 0xFBF7EC))
        .padding(18)
        .frame(maxWidth: .infinity)
        .sticker(Color.forest, radius: 28)
    }
}

/// Where the card stands at one partner: dots for the stamps, and the reward when it is ready.
struct StandingCard: View {
    let standing: LoyaltyStanding
    var body: some View {
        let o = standing.offer
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(pick(o.business.name)).font(.darb(.headline, .black))
                Spacer()
                Text(L("%lld מתוך %lld", standing.stamps, o.goal)).font(.darb(.subheadline, .heavy)).monospacedDigit()
            }
            Text("\(pick(o.title)) · \(pick(o.reward))").font(.darb(.subheadline)).foregroundStyle(.secondary)
            StampDots(stamps: standing.stamps, goal: o.goal)
            if standing.ready {
                Label(L("ההטבה מוכנה. בקשו אותה בקופה."), systemImage: "gift.fill")
                    .font(.darb(.subheadline, .heavy)).foregroundStyle(Color.onColor)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Color.mustard, in: Capsule())
            } else if standing.goal - standing.stamps == 1 {
                Text(L("עוד אחת להטבה")).font(.darb(.footnote, .bold)).foregroundStyle(Color.open)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sticker(Color.card, radius: 22, line: 2, drop: 3)
    }
}

private extension LoyaltyStanding { var goal: Int { offer.goal } }

/// The stamps as a row of circles, filled for each one given.
struct StampDots: View {
    let stamps: Int
    let goal: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<goal, id: \.self) { i in
                Circle()
                    .fill(i < stamps ? Color.mustard : Color.clear)
                    .overlay { Circle().strokeBorder(Color.onColor, lineWidth: 2) }
                    .overlay { if i < stamps { Image(systemName: "checkmark").font(.symbol(size: 11)).foregroundStyle(Color.onColor) } }
                    .frame(width: 26, height: 26)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

/// A QR code drawn sharp at any size.
struct QRCode: View {
    let text: String
    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
        } else {
            Color.clear
        }
    }

    static func make(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage, let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
