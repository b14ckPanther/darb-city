import SwiftUI

/// The chosen place's page, shaped by its kind: a printed menu, a fuel price sign, a job sheet, a branch plate;
/// or its week, or its details. A stand-in page exists only for a demo profile and is marked as one; a Darb profile's page is its own.
struct PlacePanel: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let entry: Entry
    let query: PlaceQuery
    let tab: PlaceView.Tab
    let profile: BusinessProfile?
    let accent: Color
    /// Opens a business's own site inside the app.
    var open: (URL) -> Void = { _ in }
    /// Opens Darb's plans, for the owner of a free listing.
    var plans: () -> Void = {}

    private var b: Business { entry.business }
    private var x: Extra? { store.extra(b.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch tab {
            // a business's own menu or prices when it has published them; the sample page only for a demo profile
            case .page: if let profile, !profile.items.isEmpty { clientPanel(profile) } else { pagePanel }
            case .hours: hoursPanel
            case .info: infoPanel
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(radius: Radius.card)
    }

    private func head(_ title: String, sub: String? = nil, @ViewBuilder tag: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.darb(.title3, .heavy)).lineLimit(1)
                if let sub { Text(sub).font(.darb(.caption, .medium)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            tag()
        }
        .padding(.bottom, 12)
    }

    // MARK: the kind's own page (a sample)

    private var screen: SampleScreen? {
        store.screens[b.kind] ?? query.need.flatMap { store.screens[$0.screen] }
    }

    @ViewBuilder private var pagePanel: some View {
        let need = query.need
        let items = Array((screen?.items ?? []).prefix(4)).map(Line.init)
        // this stand-in page is drawn only for a demo profile, and carries the one small mark that says so
        head(need?.pageName ?? L("מהעסק"), sub: b.name) { DemoMark() }
        switch need?.page {
        case .fuelBoard:
            let fuel = items.first { $0.key.contains("בנזין") }
            if let f = fuel, let price = f.price {
                HStack(spacing: 14) {
                    FlapBoard(text: price)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("בנזין 95")).font(.darb(.headline, .heavy))
                        Text(L("לליטר, שירות עצמי")).font(.darb(.caption, .medium)).opacity(0.65)
                    }
                    .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Color.forest, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1) }
                .padding(.bottom, 4)
            }
            ForEach(items.filter { $0.label != fuel?.label }) { menuLine($0) }
        case .branch:
            let real = x?.attr?.branchCode
            HStack(spacing: 14) {
                Text(real.map(String.init) ?? "712").figure(40, weight: .heavy)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(accent.opacity(0.5), lineWidth: 1) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(x?.attr?.bankCode.map(Self.bank) ?? b.name).font(.darb(.headline, .heavy))
                    Text(real == nil ? L("מספר סניף להדגמה") : L("מספר הסניף, מבנק ישראל")).font(.darb(.caption, .medium)).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            ForEach(items.filter { $0.key != "מספר סניף" }) { menuLine($0) }
        default:
            if items.contains(where: { $0.percent != nil }) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in stepLine(it, last: i == items.count - 1) }
            } else {
                ForEach(items) { menuLine($0) }
            }
        }
        if need?.page == .services, let t = x?.attr?.motGarageType {
            foot(L("רשום במשרד התחבורה") + ": " + Self.garageType(t))
        } else {
            foot(need?.page == .menu ? L("כך ייראה העמוד כשהעסק יעדכן את התפריט שלו.") : L("כך ייראה העמוד כשהעסק יעדכן את המחירים שלו."))
        }
    }

    private func foot(_ text: String) -> some View {
        Text(text).font(.darb(.caption)).foregroundStyle(.secondary).padding(.top, 12)
    }

    /// A line on a printed menu: the dish, a dotted leader, the price.
    private func menuLine(_ it: Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(it.label).font(.darb(.body, .bold))
                if !it.note.isEmpty { Text(it.note).font(.darb(.footnote)).foregroundStyle(.secondary).lineLimit(2) }
            }
            .layoutPriority(1)
            if it.price == nil { Spacer(minLength: 0) } else { Leader().alignmentGuide(.firstTextBaseline) { $0[.bottom] } }
            if let p = it.price {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("₪").font(.darb(.footnote, .bold)).foregroundStyle(.secondary)
                    Text(p).figure(22, weight: .heavy, relativeTo: .title3)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// A step of a job or an order: done, under way, or still waiting.
    private func stepLine(_ it: Line, last: Bool) -> some View {
        let p = it.percent ?? (it.price == nil ? 0 : -1)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3)
                    if p >= 100 {
                        Circle().fill(accent)
                        Image(systemName: "checkmark").font(.symbol(.caption)).foregroundStyle(Color.onColor)
                    } else if p > 0 {
                        Circle().trim(from: 0, to: p / 100).stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    } else if p < 0 {
                        Image(systemName: "flag.fill").font(.symbol(.caption2)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 26, height: 26)
                if !last { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(it.label).font(.darb(.body, .bold))
                if !it.note.isEmpty { Text(it.note).font(.darb(.footnote)).foregroundStyle(.secondary) }
            }
            .padding(.top, 2)
            .padding(.bottom, last ? 0 : 16)
            Spacer(minLength: 6)
            if let price = it.price {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("₪").font(.darb(.footnote, .bold)).foregroundStyle(.secondary)
                    Text(price).figure(22, weight: .heavy, relativeTo: .title3)
                }
                .environment(\.layoutDirection, .leftToRight)
            } else if p > 0, p < 100 {
                Text(verbatim: "\(Int(p))%").font(.figure(.subheadline)).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    // MARK: a Darb profile's own page

    @ViewBuilder private func clientPanel(_ c: BusinessProfile) -> some View {
        head(query.need?.pageName ?? L("מהעסק"), sub: c.tagline) {
            Label(L("מהעסק עצמו"), systemImage: "checkmark.seal.fill")
                .font(.darb(.caption2, .heavy)).foregroundStyle(accent).fixedSize()
        }
        if !c.tags.isEmpty {
            Flow(spacing: 6) {
                ForEach(c.tags, id: \.self) { t in
                    Text(t).font(.darb(.caption, .bold)).padding(.horizontal, 11).padding(.vertical, 6)
                        .background(accent.opacity(0.18), in: Capsule())
                }
            }
            .padding(.bottom, 8)
        }
        ForEach(Array(c.items.enumerated()), id: \.offset) { i, it in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%02d", i + 1)).font(.figure(.caption)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(it.label.now).font(.darb(.body, .bold))
                    if let m = it.meta?.now { Text(m).font(.darb(.footnote)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) { if i < c.items.count - 1 { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) } }
            .accessibilityElement(children: .combine)
        }
        if let action = c.action {
            // the business's own app, built by Darb: a look at it, and the way in
            Button { Analytics.log(.order, b.id); open(action.url) } label: {
                HStack(spacing: 12) {
                    if let shot = c.app, let image = UIImage(named: shot) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 64, height: 96, alignment: .top)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1) }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("%@ באפליקציה של %@", action.title, b.name)).font(.darb(.subheadline, .heavy)).multilineTextAlignment(.leading)
                        if let host = action.url.host() { Text(host).font(.darb(.caption, .medium)).foregroundStyle(.secondary) }
                        Text(L("נפתח כאן, בתוך דרב")).font(.darb(.caption2, .semibold)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.symbol(.footnote)).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .foregroundStyle(Color.ink)
            .padding(.top, 12)
        }
    }

    // MARK: hours

    /// The week as a plain table: the day and its hours, today first. When the hours are not the business's own,
    /// one quiet line says so, here and nowhere else; the button at the bottom of the page then offers to ask.
    @ViewBuilder private var hoursPanel: some View {
        head(L("השבוע"), sub: store.statusLine(entry))
        let today = OpenHours.weekday(store.now)
        VStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let d = (today + i) % 7
                HStack(spacing: 10) {
                    Text(i == 0 ? L("היום") : OpenHours.dayName(d)).font(.darb(.subheadline, i == 0 ? .heavy : .medium))
                    Spacer(minLength: 8)
                    Text(OpenHours.dayText(b.hours, day: d)).font(.darb(.subheadline, i == 0 ? .heavy : .regular)).monospacedDigit()
                        .foregroundStyle(i == 0 ? .primary : .secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background { if i == 0 { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)) } }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, -12)
        if b.demoHours {
            Text(L("השעות עדיין לא אושרו על ידי העסק.")).font(.darb(.caption)).foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }

    // MARK: details

    @ViewBuilder private var infoPanel: some View {
        head(L("פרטים"), sub: store.tagline(b))
        let listed = x?.addr.map { $0.now.count > 3 ? $0.now : store.placeName(b.place) } ?? store.placeName(b.place)
        let phone = x?.phone ?? profile?.phone
        if let front = profile?.storefront {
            // how the place looks from the street, to recognise it on arrival
            StorefrontView(name: front, initial: store.art(for: b).initial, tint: accent)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label(L("כך זה נראה כשמגיעים"), systemImage: "eye.fill").font(.darb(.caption, .heavy))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(8)
                }
                .padding(.bottom, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("תמונה של חזית המקום, כדי לזהות אותו כשמגיעים"))
        }
        info("mappin.and.ellipse", profile?.address ?? listed, Geo.distance(b.km) + " · " + L("%lld דק׳", b.minutes))
        if let p = phone, let url = Outside.phone(p) {
            Button { Analytics.log(.call, b.id); openURL(url) } label: { info("phone.fill", Outside.display(p), L("חיוג"), action: true) }
                .buttonStyle(PressStyle(scale: 0.98))
        }
        if let bank = x?.attr?.bankCode { info("building.columns.fill", Self.bank(bank), L("סניף %@", x?.attr?.branchCode.map(String.init) ?? "")) }
        if let f = x?.attr?.fuelAdminNo { info("fuelpump.fill", L("מספר רישוי תחנה"), String(f)) }
        if let (p, d) = store.nearestParking(to: b), d < 1500 { info("parkingsign", L("חניה קרובה: %@", p.name), Geo.distance(d / 1000)) }
        let amen = [(L("משלוחים"), x?.attr?.delivers), (L("טייק אוויי"), x?.attr?.takeaway), (L("ישיבה בחוץ"), x?.attr?.outdoorSeating), (L("נגיש לכיסא גלגלים"), x?.attr?.wheelchair)].filter { $0.1 == true }.map(\.0)
        if !amen.isEmpty {
            Flow(spacing: 6) {
                ForEach(amen, id: \.self) { a in
                    Label(a, systemImage: "checkmark").font(.darb(.caption, .bold)).padding(.horizontal, 11).padding(.vertical, 7).background(Color.card2, in: Capsule())
                }
            }
            .padding(.top, 12)
        }
        let links: [(String, String, URL)] = [
            (x?.wa ?? profile?.whatsapp).flatMap(Outside.whatsapp).map { ("message.fill", L("וואטסאפ"), $0) },
            (x?.web.flatMap(URL.init(string:)) ?? profile?.action?.url).map { ("globe", L("אתר"), $0) },
            x?.links?.instagram.flatMap(URL.init(string:)).map { ("camera.fill", L("אינסטגרם"), $0) },
            x?.links?.facebook.flatMap(URL.init(string:)).map { ("person.2.fill", L("פייסבוק"), $0) },
        ].compactMap { $0 }
        if !links.isEmpty {
            HStack(spacing: 8) {
                ForEach(links, id: \.1) { l in
                    Link(destination: l.2) {
                        VStack(spacing: 4) {
                            Image(systemName: l.0).font(.symbol(.body))
                            Text(l.1).font(.darb(.caption2, .bold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Color.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.top, 12)
        }
        if !store.isPaid(profile) {
            // what a free listing does not have yet, said to its owner
            Button(action: plans) {
                HStack(spacing: 10) {
                    Image(systemName: "storefront.fill").font(.symbol(.footnote)).frame(width: 34, height: 34)
                        .background(Color.card2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("זה העסק שלכם?")).font(.darb(.subheadline, .bold))
                        Text(L("לוגו, תמונות ושעות בחינם. תפריט, מחירים והזמנות בתוכנית בתשלום.")).font(.darb(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward").font(.symbol(.caption)).foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.98))
            .foregroundStyle(Color.ink)
            .padding(.top, 14)
        }
    }

    private func info(_ icon: String, _ label: String, _ value: String?, action: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.symbol(.footnote))
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(label).font(.darb(.subheadline, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            if let value {
                Text(value).font(.darb(.footnote, action ? .heavy : .medium)).monospacedDigit()
                    .foregroundStyle(action ? AnyShapeStyle(Color.ink) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, action ? 12 : 0).padding(.vertical, action ? 6 : 0)
                    .background { if action { Capsule().fill(Color.card2) } }
            }
        }
        .foregroundStyle(Color.ink)
        .frame(minHeight: 44)
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// A bank's name from its Bank of Israel code.
    static func bank(_ code: Int) -> String {
        switch code {
        case 4: L("בנק יהב")
        case 10: L("בנק לאומי")
        case 11: L("בנק דיסקונט")
        case 12: L("בנק הפועלים")
        case 14: L("בנק אוצר החייל")
        case 17: L("בנק מרכנתיל")
        case 20: L("מזרחי טפחות")
        case 31: L("הבינלאומי")
        case 46: L("בנק מסד")
        case 54: L("בנק ירושלים")
        default: L("בנק")
        }
    }
    /// What kind of garage the Ministry of Transport has it down as.
    static func garageType(_ type: String) -> String {
        switch type {
        case "testing": L("מכון בדיקה")
        case "licensing": L("מכון רישוי")
        case "agricultural": L("מוסך חקלאי")
        default: L("מוסך")
        }
    }
}

/// One line of a sample page, read out of its raw text: a label, a note, and a price or a percentage when it has one.
struct Line: Identifiable {
    let label: String
    /// The label in Hebrew, to recognise a line whatever language it is shown in.
    let key: String
    let note: String
    let price: String?
    let percent: Double?
    var id: String { key }

    init(_ raw: [Tri]) {
        let meta = raw[safe: 1]?.now ?? ""
        label = raw.first?.now ?? ""
        key = raw.first?.he ?? ""
        price = meta.firstMatch(of: /₪([\d.,]+)/).map { String($0.1) }
        percent = meta.firstMatch(of: /(\d+)%/).flatMap { Double($0.1) }
        note = Line.clean(meta.replacing(/₪[\d.,]+\s*/, with: "").replacing(/·?\s*\d+%/, with: ""))
    }

    /// Sample text keeps to the copy rules: ranges are written in words and no dashes are left.
    static func clean(_ s: String) -> String {
        var t = s.replacing(/(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})/) { L("%@ עד %@", String($0.1), String($0.2)) }
        t = t.replacing(/([א-ת]')\s*-\s*([א-ת]')/) { L("%@ עד %@", String($0.1), String($0.2)) }
        t = t.replacingOccurrences(of: "-", with: " ")
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " ·")).trimmingCharacters(in: .whitespaces)
    }
}

/// The dotted leader of a printed menu.
struct Leader: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height - 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 2))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 5]))
            .foregroundStyle(.primary.opacity(0.28))
        }
        .frame(minWidth: 12, maxWidth: .infinity)
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// A split-flap price board; the digits flip into place.
struct FlapBoard: View {
    let text: String
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(text.enumerated()), id: \.offset) { i, c in
                if c == "." {
                    Circle().fill(Color.lamp).frame(width: 5, height: 5).offset(y: 14)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: 0x14412F))
                        Rectangle().fill(.black.opacity(0.55)).frame(height: 1.5)
                        Text(String(c)).font(.figure(size: 34, .heavy)).foregroundStyle(Color.lamp)
                    }
                    .frame(width: 36, height: 52)
                    .rotation3DEffect(.degrees(shown || reduceMotion ? 0 : -90), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.6)
                    .opacity(shown ? 1 : 0)
                    .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.6).delay(Double(i) * 0.08), value: shown)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { shown = true }
        .accessibilityElement()
        .accessibilityLabel(L("%@ שקלים לליטר", text))
    }
}

/// Lays chips out in rows, wrapping to the next line when a row is full.
struct Flow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(width: proposal.width ?? .infinity, subviews).last.map { CGSize(width: proposal.width ?? $0.maxX, height: $0.maxY) } ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in rows(width: bounds.width, subviews).enumerated().flatMap({ $0.element.frames.map { (0, $0) } }).enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.1.minX, y: bounds.minY + f.1.minY), proposal: ProposedViewSize(f.1.size))
        }
    }
    private struct Row { var frames: [CGRect] = []; var maxX: CGFloat = 0; var maxY: CGFloat = 0 }
    private func rows(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()], x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += h + spacing; h = 0; rows.append(Row()) }
            rows[rows.count - 1].frames.append(CGRect(x: x, y: y, width: s.width, height: s.height))
            x += s.width + spacing; h = max(h, s.height)
            rows[rows.count - 1].maxX = max(rows[rows.count - 1].maxX, x - spacing)
            rows[rows.count - 1].maxY = y + h
        }
        return rows
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
