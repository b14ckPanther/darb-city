import SwiftUI
import UIKit
import WidgetKit

/// Darb on the Home Screen and the Lock Screen: the nearest places open now, without opening the app.
@main
struct DarbWidgets: WidgetBundle {
    var body: some Widget {
        OpenNowWidget()
        DriveLiveActivity()
    }
}

struct OpenNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OpenNow", provider: OpenNowProvider()) { entry in
            OpenNowView(entry: entry)
                .environment(\.layoutDirection, entry.lang.isRTL ? .rightToLeft : .leftToRight)
                .environment(\.locale, entry.lang.locale)
        }
        .configurationDisplayName(L("פתוח וקרוב"))
        .description(L("המקומות הפתוחים הקרובים ביותר, לפי השעה."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct OpenNowEntry: TimelineEntry {
    let date: Date
    let home: String
    let answers: [Nearest.Answer]
    /// The language the person chose in the app.
    var lang: Lang = .current
}

struct OpenNowProvider: TimelineProvider {
    func placeholder(in context: Context) -> OpenNowEntry { entry(at: .now) }
    func getSnapshot(in context: Context, completion: @escaping (OpenNowEntry) -> Void) { completion(entry(at: .now)) }

    /// A day changes every quarter of an hour: places open and close, and the needs that lead change with the hour.
    func getTimeline(in context: Context, completion: @escaping (Timeline<OpenNowEntry>) -> Void) {
        let data = Nearest.load()
        let start = Calendar.current.date(bySetting: .second, value: 0, of: .now) ?? .now
        let entries = (0..<24).map { i in entry(at: start.addingTimeInterval(Double(i) * 900), data: data) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, data: DarbData? = Nearest.load()) -> OpenNowEntry {
        // the language and the place are the ones the app last used
        Lang.reload()
        guard let data else { return OpenNowEntry(date: date, home: "", answers: []) }
        let origin = Nearest.origin(in: data)
        let all = Nearest.answers(in: data, from: origin.point, at: date)
        // open ones lead; a closed need still shows when there is room, so the widget never lies by leaving it out
        return OpenNowEntry(date: date, home: origin.place?.title ?? "", answers: all.filter { $0.status.isOpen } + all.filter { !$0.status.isOpen })
    }
}

struct OpenNowView: View {
    let entry: OpenNowEntry
    @Environment(\.widgetFamily) private var family

    private var night: Bool { !(6..<18).contains(Calendar.current.component(.hour, from: entry.date)) }
    private var ink: Color { night ? Color(hex: 0xFBF7EC) : Color(hex: 0x0B2219) }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(for: .widget) {
            night ? Color(hex: 0x051811) : Color(hex: 0xFBF7EC)
        }
    }

    // MARK: Home Screen

    private let forest = Color(hex: 0x0B2219)
    private let cream = Color(hex: 0xFBF7EC)

    /// One need as a sticker: the need's colour, a thick forest outline and a hard shadow, its name in the poster
    /// face, its object, and the minutes on a lit seven segment sign.
    private func sticker(_ a: Nearest.Answer, big: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: big ? 22 : 16, style: .continuous)
        let open = a.status.isOpen
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: big ? 4 : 2) {
                Text(a.need.short).font(.poster(big ? 30 : 22)).lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.trailing, big ? 52 : 26)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    WidgetSign(text: String(format: "%02d", min(99, a.business.minutes)), size: big ? 17 : 12, lit: open)
                    Text(L("דק׳")).font(.darb(size: big ? 12 : 9, .black))
                }
                Text(a.business.name).font(.darb(size: big ? 11 : 9, .bold)).lineLimit(1).opacity(0.8)
            }
            .padding(big ? 11 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            WidgetArt(answer: a, size: big ? 58 : 34)
                .rotationEffect(.degrees(-6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(big ? 6 : 4)
        }
        .foregroundStyle(forest)
        .background { shape.fill(open ? a.need.color : Color(hex: 0xE4DDD0)) }
        .overlay { shape.strokeBorder(forest, lineWidth: big ? 3 : 2.5) }
        .background { shape.fill(forest).offset(y: big ? 4 : 3) }
    }

    @ViewBuilder private var small: some View {
        if let a = entry.answers.first {
            sticker(a, big: true)
                .padding(.bottom, 4)
                .widgetURL(URL(string: "darb://need/\(a.need.key)"))
                .accessibilityElement(children: .combine)
        } else {
            Text(L("אין נתונים")).font(.darb(.caption)).foregroundStyle(ink)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(entry.home).font(.poster(20)).lineLimit(1)
                Circle().fill(Color(hex: 0x2FCF86)).frame(width: 6, height: 6)
                Text(L("פתוח וקרוב")).font(.darb(size: 11, .heavy)).opacity(0.7)
                Spacer()
            }
            .foregroundStyle(ink)
            HStack(spacing: 8) {
                ForEach(entry.answers.prefix(3)) { a in
                    Link(destination: URL(string: "darb://need/\(a.need.key)")!) { sticker(a, big: false) }
                        .accessibilityElement(children: .combine)
                }
            }
            .padding(.bottom, 3)
        }
    }

    // MARK: Lock Screen

    @ViewBuilder private var rectangular: some View {
        if let a = entry.answers.first {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(a.need.title) · " + L("%lld דק׳", a.business.minutes)).font(.darb(.headline, .heavy))
                Text(a.business.name).font(.darb(.caption, .semibold)).lineLimit(1)
                Text(a.status.text).font(.darb(.caption2)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "darb://need/\(a.need.key)"))
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var inline: some View {
        if let a = entry.answers.first {
            Text(verbatim: "\(a.need.title): \(a.business.name), " + L("%lld דק׳", a.business.minutes))
        }
    }
}

/// The answer's own picture: a pizza for a pizzeria, a pump for a station, or the need's object.
struct WidgetArt: View {
    static let logos = Nearest.logos()
    let answer: Nearest.Answer
    let size: CGFloat
    var body: some View {
        let art = ArtResolver.resolve(answer.business, need: answer.need, sector: nil) { UIImage(named: $0) != nil }
        Group {
            if let logo = WidgetArt.logos[answer.business.id], let image = UIImage(named: logo) {
                // the business's own logo, when it has given one
                Image(uiImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else if let r = art.render, let image = UIImage(named: r) {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: art.symbol).font(.symbol(size: size * 0.5)).foregroundStyle(answer.need.color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The lit seven segment sign, as in the app.
struct WidgetSign: View {
    let text: String
    var size: CGFloat = 14
    var lit = true
    var body: some View {
        ZStack(alignment: .trailing) {
            Text(verbatim: String(text.map { $0.isNumber ? "8" : $0 })).font(.lcd(size)).foregroundStyle(Color(hex: 0xFFC330).opacity(0.13))
            Text(verbatim: text).font(.lcd(size)).foregroundStyle(lit ? Color(hex: 0xFFC330) : Color(hex: 0x6F8A7D))
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(.horizontal, size * 0.3).padding(.vertical, size * 0.22)
        .background(Color(hex: 0x0B2219), in: RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
    }
}
