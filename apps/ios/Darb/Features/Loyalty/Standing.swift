import SwiftUI

/// Where a card stands on one offer, as the counter sees it after a scan.
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

