import SwiftUI

/// Writing to Darb, from inside the app. The form is the website's own (apps/web ContactForm): the same
/// fields, the same rules and the same words, and it posts to the same API (`POST /inquiries`).
/// When the API cannot be reached the message is not lost: it can go out as a ready email instead.
struct ContactForm: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var name = ""
    @State private var contact = ""
    @State private var business = ""
    @State private var topic: DarbAPI.Inquiry.Topic
    @State private var message = ""
    private let plan: String?

    enum Phase: Equatable { case writing, sending, sent, failed(DarbAPI.Failure) }
    @State private var phase: Phase = .writing
    @State private var problems: Set<DarbAPI.Inquiry.Field> = []
    @FocusState private var focus: Int?

    init(topic: DarbAPI.Inquiry.Topic, plan: String?) {
        _topic = State(initialValue: topic)
        self.plan = plan
    }

    private var inquiry: DarbAPI.Inquiry {
        let b = business.trimmingCharacters(in: .whitespacesAndNewlines)
        return DarbAPI.Inquiry(name: name.trimmingCharacters(in: .whitespacesAndNewlines), contact: contact.trimmingCharacters(in: .whitespacesAndNewlines),
                               businessName: b.isEmpty ? nil : b, topic: topic, plan: topic == .plan ? plan : nil,
                               message: message.trimmingCharacters(in: .whitespacesAndNewlines), locale: store.lang.rawValue)
    }

    var body: some View {
        ScrollView {
            if phase == .sent { thanks } else { form }
        }
        .scrollDismissesKeyboard(.interactively)
        .page(L("web.messages.contactUs"))
        .task {
            // `-darbFormFill YES` writes a test message into the form, and `-darbFormSend YES` sends it:
            // for checking the form against a test server (`-darbAPI`), never against the real one
            guard UserDefaults.standard.bool(forKey: "darbFormFill"), name.isEmpty else { return }
            name = "Test"; contact = "050 000 0000"; message = "A test message from the app's own checks."
            if UserDefaults.standard.bool(forKey: "darbFormSend"), UserDefaults.standard.string(forKey: "darbAPI") != nil { await send() }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("web.contact.title")).display(30, relativeTo: .title)
                Text(L("web.contact.lead")).font(.darb(.subheadline)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
            if topic == .plan, let plan, let p = store.promo.plans.first(where: { $0.slug == plan }) {
                Label(L("web.contact.form.aboutPlan", p.title), systemImage: "rectangle.stack.fill").font(.darb(.footnote, .bold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.lamp.opacity(0.3), in: Capsule())
            }
            Field(label: L("web.contact.form.name"), error: problems.contains(.name) ? L("web.contact.form.errors.name") : nil) {
                TextField("", text: $name).textContentType(.name).focused($focus, equals: 0).submitLabel(.next).onSubmit { focus = 1 }
            }
            Field(label: L("web.contact.form.contact"), hint: L("web.contact.form.contactHint"), error: problems.contains(.contact) ? L("web.contact.form.errors.contact") : nil) {
                TextField("", text: $contact).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: 1).submitLabel(.next).onSubmit { focus = 2 }
                    .environment(\.layoutDirection, .leftToRight).multilineTextAlignment(store.lang.isRTL ? .trailing : .leading)
            }
            Field(label: L("web.contact.form.business"), optional: true) {
                TextField("", text: $business).textContentType(.organizationName).focused($focus, equals: 2).submitLabel(.next).onSubmit { focus = 3 }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L("web.contact.form.topic")).font(.darb(.footnote, .bold))
                Flow(spacing: 8) {
                    ForEach(DarbAPI.Inquiry.Topic.allCases.filter { $0 != .plan || plan != nil }, id: \.self) { t in
                        let on = t == topic
                        Button { withAnimation(reduceMotion ? nil : Motion.select) { topic = t }; Haptic.tap() } label: {
                            Text(L("web.contact.form.topics." + t.rawValue)).font(.darb(.subheadline, .semibold))
                                .padding(.horizontal, 14).frame(height: 44)
                                .foregroundStyle(on ? Color.canvas : Color.ink)
                                .background(on ? Color.ink : Color.card, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle(scale: 0.96))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            Field(label: L("web.contact.form.message"),
                  error: problems.contains(.messageShort) ? L("web.contact.form.errors.messageShort") : problems.contains(.messageLong) ? L("web.contact.form.errors.messageLong") : nil) {
                TextEditor(text: $message).focused($focus, equals: 3)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .padding(.vertical, 8).padding(.horizontal, -5)
            }
            if case .failed(let why) = phase { failure(why) }
            Button { Task { await send() } } label: {
                Text(phase == .sending ? L("web.contact.form.sending") : L("web.contact.form.send"))
            }
            .buttonStyle(MainButtonStyle(busy: phase == .sending))
            .disabled(phase == .sending)
            Button { openURL(DarbAPI.instagram) } label: {
                Text(L("web.contact.instagramLine")).font(.darb(.footnote, .semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 6)
    }

    /// What went wrong, in plain words, and another way to send the same message.
    private func failure(_ why: DarbAPI.Failure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(why == .tooMany ? L("web.contact.form.errors.tooMany") : L("web.contact.form.errors.failed"), systemImage: "exclamationmark.circle.fill")
                .font(.darb(.footnote, .semibold)).fixedSize(horizontal: false, vertical: true)
            if why != .tooMany, let mail = DarbAPI.mail(subject: L("הודעה מהאפליקציה של דרב"), body: mailBody) {
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
        .accessibilityElement(children: .contain)
    }

    private var mailBody: String {
        let i = inquiry
        return ([i.message, ""] + [i.name, i.contact, i.businessName ?? ""].filter { !$0.isEmpty }).joined(separator: "\n")
    }

    private var thanks: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark").font(.symbol(size: 30))
                .frame(width: 76, height: 76)
                .foregroundStyle(Color.onColor)
                .background(Color(hex: 0x3DDC97), in: Circle())
                .padding(.top, 50)
            Text(L("web.contact.form.thanksTitle")).display(28, relativeTo: .title)
            Text(L("web.contact.form.thanksBody")).font(.darb(.subheadline)).foregroundStyle(.secondary)
            Button {
                message = ""
                phase = .writing
            } label: { Text(L("web.contact.form.sendAnother")) }
                .buttonStyle(MainButtonStyle(quiet: true))
                .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func send() async {
        focus = nil
        let i = inquiry
        problems = i.problems()
        guard problems.isEmpty else { Haptic.tap(); return }
        phase = .sending
        do {
            try await DarbAPI.send(i)
            withAnimation(reduceMotion ? nil : Motion.land) { phase = .sent }
            Haptic.done()
        } catch {
            withAnimation(reduceMotion ? nil : Motion.swap) { phase = .failed(error) }
        }
    }
}
