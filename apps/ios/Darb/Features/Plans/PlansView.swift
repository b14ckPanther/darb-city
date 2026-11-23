import SwiftUI

/// Darb's plans for a business, as the website's pricing page has them: the same names, prices,
/// features and notes, from packages/seed/data/plans.json.
struct PlansView: View {
    @Environment(Store.self) private var store
    @Binding var path: [MenuPage]

    var body: some View {
        let promo = store.promo
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(promo.text("pricing.eyebrow")).eyebrow().foregroundStyle(Color.gold)
                    Text(promo.text("pricing.title")).display(30, relativeTo: .title).fixedSize(horizontal: false, vertical: true)
                    Text(promo.text("pricing.intro")).font(.darb(.subheadline)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                ForEach(promo.plans) { plan in card(plan) }

                block(promo.text("pricing.termsTitle")) {
                    ForEach(lines(promo.text("pricing.terms")), id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Color.ink.opacity(0.35)).frame(width: 4, height: 4).offset(y: -3)
                            Text(line).font(.darb(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                block(promo.text("pricing.faqTitle")) {
                    let qa = lines(promo.text("pricing.faq"))
                    ForEach(Array(stride(from: 0, to: qa.count - 1, by: 2)), id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(qa[i]).font(.darb(.subheadline, .bold)).fixedSize(horizontal: false, vertical: true)
                            Text(qa[i + 1]).font(.darb(.footnote)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 3)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(promo.text("pricing.contactTitle")).font(.darb(.title3, .heavy))
                    Text(promo.text("pricing.contactBody")).font(.darb(.subheadline)).opacity(0.75)
                    Button { path.append(.contact(topic: .general, plan: nil)) } label: { Text(L("web.messages.contactUs")) }
                        .buttonStyle(MainButtonStyle())
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface(radius: Radius.card, fill: .card2)
            }
            .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 6)
        }
        .page(L("תוכניות ומחירים"))
    }

    private func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func block(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.darb(.headline, .heavy))
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: Radius.card)
    }

    private func card(_ plan: Plan) -> some View {
        let promo = store.promo
        let lit = plan.highlighted
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.title).font(.darb(.title3, .heavy))
                Spacer(minLength: 8)
                if lit {
                    Text(promo.text("pricing.badge")).font(.darb(.caption2, .heavy))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(Color.onColor).background(Color.lamp, in: Capsule())
                }
            }
            Text(plan.tagline.now).font(.darb(.subheadline)).opacity(0.75).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let m = plan.monthly, m > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(verbatim: "₪").font(.darb(.title3, .bold)).opacity(0.6)
                        Text(verbatim: "\(m)").figure(40)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                } else {
                    Text(plan.monthly == 0 ? promo.text("pricing.free") : promo.text("pricing.custom")).display(30, relativeTo: .title)
                }
                if let note = plan.priceNote?.now, !note.isEmpty { Text(note).font(.darb(.footnote, .medium)).opacity(0.65) }
            }
            if let setup = plan.setup, setup > 0 {
                Text(promo.text("pricing.setup").replacingOccurrences(of: "{amount}", with: "₪\(setup)").replacingOccurrences(of: "+ ", with: ""))
                    .font(.darb(.caption, .semibold)).opacity(0.65)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(plan.points, id: \.self) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: "checkmark").font(.symbol(.caption)).foregroundStyle(lit ? Color.lamp : Color.open)
                        Text(f).font(.darb(.footnote)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)
            Button { path.append(plan.monthly == 0 ? .join(plan: nil) : .contact(topic: .plan, plan: plan.slug)) } label: {
                Text(plan.cta?.now ?? L("web.messages.contactUs"))
            }
            .buttonStyle(PlanButtonStyle(lit: lit))
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(lit ? Color.white : Color.ink)
        .background {
            if lit {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.onColor)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            }
        }
        .modifier(PlainCard(on: !lit))
        .accessibilityElement(children: .contain)
    }
}

private struct PlainCard: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View { if on { content.surface(radius: Radius.card) } else { content } }
}

private struct PlanButtonStyle: ButtonStyle {
    let lit: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.darb(.headline, .heavy))
            .frame(maxWidth: .infinity).frame(height: 50)
            .foregroundStyle(lit ? Color.onColor : Color.canvas)
            .background(lit ? Color.lamp : Color.ink, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.9), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
