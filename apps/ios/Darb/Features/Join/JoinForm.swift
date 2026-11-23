import MapKit
import SwiftUI

/// Adding a business to Darb, from inside the app. It asks what the website's join form asks
/// (apps/web /join, `JoinCreateSchema`) in the website's own words, and posts to the same API (`POST /join`).
/// Photos and a logo are added later, with the Darb team: the app does not upload pictures yet.
struct JoinForm: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The plan the owner came from, to tell the team.
    let plan: String?

    @State private var name = ""
    @State private var kind: Kind?
    @State private var place: Place?
    /// Where the map was last sent: a town's centre, or the owner's own position.
    @State private var target: Coordinate?
    @State private var close = false
    @State private var point: Coordinate?
    @State private var address = ""
    @State private var phone = ""
    @State private var whatsapp = ""
    @State private var sameNumber = true
    @State private var website = ""
    @State private var instagram = ""
    @State private var facebook = ""
    @State private var week: [Int: DaySpan] = [:]
    @State private var about = ""
    @State private var ownerName = ""
    @State private var ownerPhone = ""
    @State private var ownerEmail = ""
    @State private var note = ""

    struct DaySpan: Equatable { var open: Int; var close: Int }
    enum Problem: Hashable { case name, kind, place, phone, whatsapp, ownerName, ownerPhone, ownerEmail }
    enum Phase: Equatable { case writing, sending, sent, failed(DarbAPI.Failure) }
    enum Picker: Identifiable { case kind, place; var id: Self { self } }

    @State private var problems: Set<Problem> = []
    @State private var phase: Phase = .writing
    @State private var picker: Picker?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if phase == .sent { done } else { form(proxy) }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .page(L("web.landing.join.list"))
        .task {
            // `-darbFormFill YES` fills the form with a test business, for checking it against a test server (`-darbAPI`)
            guard UserDefaults.standard.bool(forKey: "darbFormFill"), name.isEmpty else { return }
            name = "Test"; kind = store.kinds["bakeries"]; place = store.places["sakhnin"]
            ownerName = "Test"; ownerPhone = "050-0000000"
            week = Dictionary(uniqueKeysWithValues: (0...4).map { ($0, DaySpan(open: 540, close: 1080)) })
        }
        .sheet(item: $picker) { which in
            switch which {
            case .kind:
                Chooser(title: L("web.join.check.type"), prompt: L("web.join.check.typeSearch"), items: store.data.kinds,
                        label: { $0.title }, detail: { store.sectors[$0.sector]?.title ?? "" }, words: { $0.words.joined(separator: " ").lowercased() }) { kind = $0 }
            case .place:
                Chooser(title: L("web.join.check.town"), prompt: L("web.join.check.townSearch"), items: store.towns(matching: ""),
                        label: { $0.title }, detail: { _ in "" }, words: { ($0.name.searchKey + " " + $0.aliases.joined(separator: " ")).lowercased() }) { p in
                    place = p
                    move(to: Coordinate(lat: p.lat, lng: p.lng))
                }
            }
        }
    }

    // MARK: the form

    private func form(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("web.join.title")).display(30, relativeTo: .title).fixedSize(horizontal: false, vertical: true)
                Text(L("web.join.lead")).font(.darb(.subheadline)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            section(L("web.join.check.business")) {
                Field(label: L("web.join.check.name"), hint: L("web.join.check.nameHint"), error: problems.contains(.name) ? L("web.join.errors.name") : nil) {
                    TextField("", text: $name).textContentType(.organizationName)
                }
                .id(Problem.name)
                choice(L("web.join.check.type"), value: kind?.title, error: problems.contains(.kind) ? L("web.join.errors.kind") : nil) { picker = .kind }
                    .id(Problem.kind)
                choice(L("web.join.check.town"), value: place?.title, error: problems.contains(.place) ? L("web.join.errors.place") : nil) { picker = .place }
                    .id(Problem.place)
            }

            section(L("web.join.check.location")) {
                map
                Field(label: L("web.join.check.address"), optional: true) { TextField("", text: $address).textContentType(.fullStreetAddress) }
            }

            section(L("web.join.check.contact")) {
                Field(label: L("web.join.check.phone"), optional: true, error: problems.contains(.phone) ? L("web.join.errors.phone") : nil) { number($phone) }
                    .id(Problem.phone)
                Toggle(isOn: $sameNumber) { Text(L("web.join.check.sameAsPhone")).font(.darb(.subheadline, .semibold)) }
                    .tint(Color.open).frame(minHeight: 44)
                if !sameNumber {
                    Field(label: L("web.join.check.whatsapp"), optional: true, error: problems.contains(.whatsapp) ? L("web.join.errors.whatsapp") : nil) { number($whatsapp) }
                        .id(Problem.whatsapp)
                }
                Field(label: L("web.join.check.website"), optional: true) { latin($website, keyboard: .URL) }
                Field(label: L("web.join.check.instagram"), optional: true, hint: L("web.join.check.handleHint")) { latin($instagram, keyboard: .twitter) }
                Field(label: L("web.join.check.facebook"), optional: true) { latin($facebook, keyboard: .URL) }
            }

            section(L("web.join.check.hours")) { hours }

            section(L("web.join.check.description")) {
                Field(label: L("web.join.check.description"), optional: true, hint: L("web.join.check.descriptionHint")) {
                    TextEditor(text: $about).scrollContentBackground(.hidden).frame(minHeight: 90).padding(.vertical, 8).padding(.horizontal, -5)
                }
            }

            section(L("web.join.check.owner"), note: L("web.join.check.ownerHint")) {
                Field(label: L("web.join.check.ownerName"), error: problems.contains(.ownerName) ? L("web.join.errors.ownerName") : nil) {
                    TextField("", text: $ownerName).textContentType(.name)
                }
                .id(Problem.ownerName)
                Field(label: L("web.join.check.ownerPhone"), error: problems.contains(.ownerPhone) ? L("web.join.errors.ownerPhone") : nil) { number($ownerPhone) }
                    .id(Problem.ownerPhone)
                Field(label: L("web.join.check.ownerEmail"), optional: true, error: problems.contains(.ownerEmail) ? L("web.join.errors.ownerEmail") : nil) {
                    latin($ownerEmail, keyboard: .emailAddress).textContentType(.emailAddress)
                }
                .id(Problem.ownerEmail)
                Field(label: L("web.join.check.note"), optional: true) {
                    TextEditor(text: $note).scrollContentBackground(.hidden).frame(minHeight: 70).padding(.vertical, 8).padding(.horizontal, -5)
                }
            }

            if !problems.isEmpty {
                Label(L("web.join.errors.fix"), systemImage: "exclamationmark.circle.fill").font(.darb(.footnote, .semibold)).foregroundStyle(Color.shut)
            }
            if case .failed(let why) = phase { failure(why) }
            Button { Task { await send(proxy) } } label: { Text(phase == .sending ? L("web.join.check.sending") : L("web.join.check.send")) }
                .buttonStyle(MainButtonStyle(busy: phase == .sending))
                .disabled(phase == .sending)
            Text(L("תמונות ולוגו מוסיפים אחר כך, יחד עם הצוות של דרב.")).font(.darb(.caption)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 6)
    }

    private func section(_ title: String, note: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.darb(.headline, .heavy)).accessibilityAddTraits(.isHeader)
                if let note { Text(note).font(.darb(.caption)).foregroundStyle(.secondary) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card2.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    /// A field that opens a list to choose from.
    private func choice(_ label: String, value: String?, error: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Field(label: label, error: error) {
                HStack {
                    Text(value ?? L("לבחור")).foregroundStyle(value == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.ink))
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down").font(.symbol(.caption)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    private func number(_ text: Binding<String>) -> some View {
        TextField("", text: text).keyboardType(.phonePad).textContentType(.telephoneNumber)
            .environment(\.layoutDirection, .leftToRight).multilineTextAlignment(store.lang.isRTL ? .trailing : .leading)
    }

    private func latin(_ text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField("", text: text).keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
            .environment(\.layoutDirection, .leftToRight).multilineTextAlignment(store.lang.isRTL ? .trailing : .leading)
    }

    // MARK: where the business is

    /// The map moves under a fixed pin, so the owner puts the pin on the entrance by moving the map.
    private var map: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                PinMap(centre: target ?? store.origin, span: close ? 0.002 : 0.02, point: $point)
                    // a new town or a new position starts the map again there
                    .id(target)
                Image(systemName: "mappin").font(.system(size: 30, weight: .bold)).foregroundStyle(Color.shut)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    .offset(y: -14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Color.ink.opacity(0.1), lineWidth: 1) }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(L("web.join.check.location"))
            Text(place == nil ? L("קודם בוחרים עיר או ישוב, ואז מזיזים את המפה עד שהסיכה על הכניסה.") : L("מזיזים את המפה עד שהסיכה בדיוק על הכניסה."))
                .font(.darb(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if store.location.access == .allowed, let me = store.location.coordinate {
                Button { move(to: me, span: 0.002) } label: {
                    Label(L("web.join.find.here"), systemImage: "location.fill").font(.darb(.subheadline, .bold))
                        .padding(.horizontal, 14).frame(height: 44).background(Color.card, in: Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.96))
            }
        }
    }

    private func move(to c: Coordinate, span: Double = 0.02) {
        point = c
        close = span < 0.01
        target = c
    }

    // MARK: hours

    private var hours: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("web.join.hours.presets")).font(.darb(.footnote, .bold))
            Flow(spacing: 8) {
                preset(L("web.join.hours.sunThu")) {
                    var w: [Int: DaySpan] = [:]
                    for d in 0...4 { w[d] = DaySpan(open: 540, close: 1080) }
                    w[5] = DaySpan(open: 540, close: 840)
                    week = w
                }
                preset(L("web.join.hours.everyDay")) { week = Dictionary(uniqueKeysWithValues: (0...6).map { ($0, DaySpan(open: 540, close: 1080)) }) }
                preset(L("web.join.hours.allDay")) { week = Dictionary(uniqueKeysWithValues: (0...6).map { ($0, DaySpan(open: 0, close: 1440)) }) }
                if !week.isEmpty { preset(L("לנקות")) { week = [:] } }
            }
            VStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { d in
                    let on = week[d] != nil
                    HStack(spacing: 8) {
                        Toggle(isOn: Binding(get: { on }, set: { week[d] = $0 ? DaySpan(open: 540, close: 1080) : nil })) {
                            Text(OpenHours.dayName(d)).font(.darb(.subheadline, on ? .bold : .regular))
                        }
                        .tint(Color.open)
                        .frame(width: 136)
                        Spacer(minLength: 0)
                        if let s = week[d] {
                            if s.open == 0 && s.close >= 1440 {
                                Text(L("24 שעות")).font(.darb(.footnote, .semibold)).foregroundStyle(.secondary)
                            } else {
                                time(Binding(get: { s.open }, set: { week[d]?.open = $0 }))
                                Text(L("web.join.hours.to")).font(.darb(.caption)).foregroundStyle(.secondary)
                                time(Binding(get: { s.close }, set: { week[d]?.close = $0 }))
                            }
                        } else {
                            Text(L("סגור")).font(.darb(.footnote)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 48)
                }
            }
        }
    }

    private func preset(_ title: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(reduceMotion ? nil : Motion.select) { action() }; Haptic.tap() } label: {
            Text(title).font(.darb(.footnote, .semibold)).padding(.horizontal, 12).frame(height: 44).background(Color.card, in: Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.96))
    }

    private func time(_ minutes: Binding<Int>) -> some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.date(bySettingHour: (minutes.wrappedValue % 1440) / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now) ?? .now },
            set: { minutes.wrappedValue = OpenHours.minuteOfDay($0) }), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "en_GB"))
    }

    // MARK: sending

    static func clock(_ m: Int) -> String { m >= 1440 ? "24:00" : String(format: "%02d:%02d", m / 60, m % 60) }

    /// The request as the API reads it, or what is wrong with the form.
    func request() -> (join: DarbAPI.Join?, problems: Set<Problem>) {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        var bad: Set<Problem> = []
        if t(name).isEmpty { bad.insert(.name) }
        if kind == nil { bad.insert(.kind) }
        if place == nil { bad.insert(.place) }
        if !t(phone).isEmpty, !DarbAPI.Check.joinPhone(t(phone)) { bad.insert(.phone) }
        let wa = sameNumber ? t(phone) : t(whatsapp)
        if !sameNumber, !wa.isEmpty, !DarbAPI.Check.joinPhone(wa) { bad.insert(.whatsapp) }
        if t(ownerName).count < 2 { bad.insert(.ownerName) }
        if !DarbAPI.Check.joinPhone(t(ownerPhone)) { bad.insert(.ownerPhone) }
        if !t(ownerEmail).isEmpty, !DarbAPI.Check.email(t(ownerEmail)) { bad.insert(.ownerEmail) }
        guard bad.isEmpty, let kind, let place else { return (nil, bad) }
        let lang = store.lang.rawValue
        let at = point ?? Coordinate(lat: place.lat, lng: place.lng)
        var links: [String: String] = [:]
        if !t(instagram).isEmpty { links["instagram"] = t(instagram) }
        if !t(facebook).isEmpty { links["facebook"] = t(facebook) }
        var weekly: [String: [DarbAPI.Join.Interval]] = [:]
        for (d, s) in week { weekly[String(d)] = [.init(open: Self.clock(s.open), close: Self.clock(s.close))] }
        var memo = t(note)
        if let plan { memo = (memo.isEmpty ? "" : memo + "\n") + "plan: \(plan)" }
        let join = DarbAPI.Join(
            name: [lang: t(name)], kindSlug: kind.slug, placeSlug: place.slug, lat: at.lat, lng: at.lng,
            address: t(address).isEmpty ? [:] : [lang: t(address)],
            phone: t(phone).isEmpty ? nil : t(phone), whatsapp: wa.isEmpty ? nil : wa, website: t(website).isEmpty ? nil : t(website),
            links: links, hours: .init(weekly: weekly), description: t(about).isEmpty ? [:] : [lang: t(about)],
            owner: .init(name: t(ownerName), phone: t(ownerPhone), email: t(ownerEmail).isEmpty ? nil : t(ownerEmail)),
            note: memo.isEmpty ? nil : memo, locale: lang)
        return (join, [])
    }

    private func send(_ proxy: ScrollViewProxy) async {
        let r = request()
        withAnimation(reduceMotion ? nil : Motion.swap) { problems = r.problems }
        guard let join = r.join else {
            Haptic.tap()
            let order: [Problem] = [.name, .kind, .place, .phone, .whatsapp, .ownerName, .ownerPhone, .ownerEmail]
            if let first = order.first(where: r.problems.contains) { withAnimation(reduceMotion ? nil : Motion.land) { proxy.scrollTo(first, anchor: .center) } }
            return
        }
        phase = .sending
        do {
            try await DarbAPI.send(join)
            withAnimation(reduceMotion ? nil : Motion.land) { phase = .sent }
            Haptic.done()
        } catch {
            withAnimation(reduceMotion ? nil : Motion.swap) { phase = .failed(error) }
        }
    }

    private func failure(_ why: DarbAPI.Failure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(why == .tooMany ? L("web.join.errors.tooMany") : L("web.join.errors.failed"), systemImage: "exclamationmark.circle.fill")
                .font(.darb(.footnote, .semibold)).fixedSize(horizontal: false, vertical: true)
            if why != .tooMany, let mail = DarbAPI.mail(subject: L("web.landing.join.list") + ": " + name, body: mailBody) {
                Button { openURL(mail) } label: {
                    Label(L("לשלוח במייל במקום"), systemImage: "envelope.fill").font(.darb(.subheadline, .heavy))
                        .padding(.horizontal, 14).frame(height: 44)
                        .foregroundStyle(Color.canvas).background(Color.ink, in: Capsule())
                }
                .buttonStyle(PressStyle(scale: 0.96))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.shut.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private var mailBody: String {
        var lines = [name, kind?.title ?? "", place?.title ?? "", address, phone, website, ""]
        if let p = point { lines.append(String(format: "%.5f, %.5f", p.lat, p.lng)) }
        lines += ["", ownerName, ownerPhone, ownerEmail, note]
        return lines.joined(separator: "\n")
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark").font(.symbol(size: 30))
                .frame(width: 76, height: 76)
                .foregroundStyle(Color.onColor)
                .background(Color(hex: 0x3DDC97), in: Circle())
                .padding(.top, 50)
            Text(L("web.join.done.title")).display(28, relativeTo: .title)
            Text(L("web.join.done.body")).font(.darb(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// A list to choose one thing from, with search: a kind of business, or a town.
private struct Chooser<Item: Identifiable>: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let title: String
    let prompt: String
    let items: [Item]
    let label: (Item) -> String
    let detail: (Item) -> String
    let words: (Item) -> String
    let pick: (Item) -> Void
    @State private var q = ""

    var body: some View {
        let needle = q.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = needle.isEmpty ? items : items.filter { words($0).contains(needle) }
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.darb(.title2, .heavy))
                Spacer()
                CloseButton { dismiss() }
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 8)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.symbol(.body))
                TextField(prompt, text: $q).autocorrectionDisabled().font(.darb(.body, .medium))
            }
            .padding(.horizontal, 16).frame(height: 50)
            .background(Color.card, in: Capsule())
            .padding(.horizontal, 16).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 6) {
                    if shown.isEmpty { Notice(symbol: "magnifyingglass", title: L("web.join.check.noMatch")) }
                    ForEach(shown) { item in
                        Button { pick(item); dismiss() } label: {
                            HStack {
                                Text(label(item)).font(.darb(.subheadline, .bold)).multilineTextAlignment(.leading)
                                Spacer(minLength: 6)
                                Text(detail(item)).font(.darb(.caption)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 14).frame(minHeight: 50)
                            .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color.canvas)
        .foregroundStyle(Color.ink)
        .environment(\.layoutDirection, store.lang.isRTL ? .rightToLeft : .leftToRight)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
    }
}

/// A map that moves under a fixed pin and reports the point under it.
private struct PinMap: View {
    @Binding var point: Coordinate?
    @State private var camera: MapCameraPosition

    init(centre: Coordinate, span: Double, point: Binding<Coordinate?>) {
        _point = point
        _camera = State(initialValue: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: centre.lat, longitude: centre.lng),
                                                                 span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))))
    }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom])
            .onMapCameraChange(frequency: .onEnd) { ctx in
                point = Coordinate(lat: ctx.region.center.latitude, lng: ctx.region.center.longitude)
            }
    }
}
