import SwiftUI

/// Signing in for Darb's admins and partners' staff: an email, then the six digit code sent to it. A new email
/// becomes an account the same way. Once in, the page shows who is signed in and what they can open.
struct SignInView: View {
    @Bindable private var account = Account.shared
    @State private var email = ""
    @State private var code = ""
    @FocusState private var focused: Bool
    var open: (MenuPage) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch account.step {
                case .signedOut: emailStep
                case .codeSent(let address, let isNew): codeStep(address, isNew: isNew)
                case .signedIn: signedIn
                }
                if let error = account.error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.darb(.subheadline, .bold)).foregroundStyle(Color.shut)
                }
            }
            .padding(16)
        }
        .background(Color.canvas)
        .page(L("כניסה לצוות"))
        .disabled(account.busy)
        .overlay { if account.busy { ProgressView() } }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("לצוות של דרב ושל העסקים השותפים: ניהול, והחתמת כרטיסים בקופה."))
                .font(.darb(.subheadline)).foregroundStyle(.secondary)
            TextField(L("מייל"), text: $email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
                .font(.darb(.body)).padding(.horizontal, 14).frame(height: 52)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($focused).onAppear { focused = true }
                .submitLabel(.send).onSubmit { Task { await account.send(email: email) } }
            wide(L("לשלוח קוד")) { await account.send(email: email) }
        }
    }

    private func codeStep(_ address: String, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? L("שלחנו קוד ל %@ כדי לפתוח לכם חשבון.", address) : L("שלחנו קוד ל %@.", address))
                .font(.darb(.subheadline)).foregroundStyle(.secondary)
            TextField(L("הקוד"), text: $code)
                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                .font(.system(size: 28, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .frame(height: 60)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($focused).onAppear { focused = true }
                .onChange(of: code) { _, v in if v.filter(\.isNumber).count == 6 { Task { await account.verify(code: v) } } }
            wide(L("להיכנס")) { await account.verify(code: code) }
            Button(L("מייל אחר")) { code = ""; account.startOver() }.font(.darb(.subheadline, .bold))
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowGroup {
                MenuRow(symbol: "person.crop.circle.fill", title: account.email ?? L("מחוברים"),
                        detail: account.isAdmin ? L("מנהל דרב") : account.stampsFor.isEmpty ? L("עוד לא צוות של עסק") : L("צוות")) { EmptyView() }
            }
            if account.isAdmin || !account.stampsFor.isEmpty {
                Button { open(.stamp) } label: {
                    MenuRow(symbol: "qrcode.viewfinder", title: L("החתמת כרטיס"), detail: L("סריקה במצלמה, החתמה בנגיעה"), tint: .mustard)
                }
                .buttonStyle(PressStyle(scale: 0.985))
            }
            if account.isAdmin {
                Button { open(.admin) } label: {
                    MenuRow(symbol: "slider.horizontal.3", title: L("ניהול"), detail: L("הטבות, קישורי צוות וכיסוי לפי ישוב"), tint: Color(hex: 0x66CCFF))
                }
                .buttonStyle(PressStyle(scale: 0.985))
            }
            if !account.isAdmin && account.stampsFor.isEmpty {
                Text(L("כדי להחתים כרטיסים, פתחו את קישור ההזמנה שדרב שלח לעסק."))
                    .font(.darb(.footnote)).foregroundStyle(.secondary)
            }
            Button(role: .destructive) { Task { await account.signOut() } } label: {
                Text(L("יציאה")).font(.darb(.body, .bold)).frame(maxWidth: .infinity).frame(height: 48)
            }
        }
        .task { await account.refreshRoles() }
    }

    private func wide(_ title: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(.darb(.headline, .heavy)).foregroundStyle(Color.onColor)
                .frame(maxWidth: .infinity).frame(height: 54)
                .sticker(.mustard, radius: 18, line: 2.5, drop: 3)
        }
        .buttonStyle(PressStyle(scale: 0.97))
    }
}
