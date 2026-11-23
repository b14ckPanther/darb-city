import ClerkKit
import Foundation
import Observation

/// Signing in, for Darb's admins and partners' staff: the same accounts as the web admin and the helper app.
/// A person signs in with a code sent to their email; a new email becomes a new account the same way. What they
/// may do is decided by Darb's server, never here: whether they are an admin, and which businesses they stamp for.
@MainActor @Observable
final class Account {
    static let shared = Account()

    enum Step: Equatable { case signedOut, codeSent(email: String, newAccount: Bool), signedIn }

    private(set) var step: Step = .signedOut
    private(set) var email: String?
    /// Whether Darb's server sees this person as an admin.
    private(set) var isAdmin = false
    /// The server could not be asked (offline, or it refused the session): neither admin nor staff is known.
    private(set) var rolesUnknown = false
    /// The offers this person stamps cards for (admins: every active one).
    private(set) var stampsFor: [LoyaltyOffer] = []
    private(set) var busy = false
    var error: String?

    /// Sign-in needs Clerk's publishable key in the app's Info.plist (DarbClerkKey); without it the menu hides sign-in.
    static var key: String? {
        (Bundle.main.object(forInfoDictionaryKey: "DarbClerkKey") as? String).flatMap { $0.hasPrefix("pk_") ? $0 : nil }
    }
    static var available: Bool { key != nil }

    private var configured = false
    private var signIn: SignIn?
    private var signUp: SignUp?

    private func clerk() -> Clerk? {
        guard let key = Self.key else { return nil }
        if !configured { Clerk.configure(publishableKey: key); configured = true }
        return Clerk.shared
    }

    /// At launch: picks up a session kept from last time, and what the server lets this person do.
    func restore() async {
        guard let clerk = clerk() else { return }
        _ = try? await clerk.refreshClient()
        if clerk.session?.status == .active { await signedIn() }
    }

    /// Sends a code to the email: to sign in, or, for an email Darb has not seen, to make the account.
    func send(email raw: String) async {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let clerk = clerk(), DarbAPI.Check.email(email) else { error = L("כתובת המייל לא תקינה"); return }
        busy = true; defer { busy = false }
        error = nil
        do {
            signIn = try await clerk.auth.signInWithEmailCode(emailAddress: email)
            signUp = nil
            step = .codeSent(email: email, newAccount: false)
        } catch let e as ClerkAPIError where e.code == "form_identifier_not_found" {
            do {
                let up = try await clerk.auth.signUp(emailAddress: email)
                signUp = try await up.sendEmailCode()
                signIn = nil
                step = .codeSent(email: email, newAccount: true)
            } catch { self.error = Self.message(error) }
        } catch { self.error = Self.message(error) }
    }

    func verify(code raw: String) async {
        let code = raw.filter(\.isNumber)
        guard code.count == 6 else { error = L("הקוד הוא שש ספרות"); return }
        busy = true; defer { busy = false }
        error = nil
        do {
            if let signIn {
                let done = try await signIn.verifyCode(code)
                guard done.status == .complete else { error = L("הכניסה לא הושלמה. נסו שוב."); return }
            } else if let signUp {
                let done = try await signUp.verifyEmailCode(code)
                guard done.status == .complete else { error = L("הכניסה לא הושלמה. נסו שוב."); return }
            }
            await signedIn()
        } catch { self.error = Self.message(error) }
    }

    func startOver() { step = .signedOut; signIn = nil; signUp = nil; error = nil }

    func signOut() async {
        try? await clerk()?.auth.signOut()
        step = .signedOut; email = nil; isAdmin = false; rolesUnknown = false; stampsFor = []
    }

    /// A fresh session token for Darb's server.
    func token() async -> String? {
        guard let session = clerk()?.session, session.status == .active else { return nil }
        return try? await session.getToken()
    }

    /// Reads what this person may do: admin, and the offers they stamp for.
    func refreshRoles() async {
        async let admin = DarbAPI.adminStatus()
        async let offers = LoyaltyAPI.staffOffers()
        let status = await admin
        isAdmin = status == 200
        rolesUnknown = status != 200 && status != 403
        stampsFor = (try? await offers) ?? []
    }

    private func signedIn() async {
        step = .signedIn
        email = clerk()?.user?.primaryEmailAddress?.emailAddress
        await refreshRoles()
    }

    private static func message(_ error: Error) -> String {
        if let e = error as? ClerkAPIError {
            switch e.code {
            case "form_code_incorrect": return L("הקוד לא נכון")
            case "verification_expired": return L("הקוד פג. שלחו קוד חדש.")
            case "too_many_requests": return L("יותר מדי ניסיונות. נסו שוב בעוד כמה דקות.")
            default: return e.longMessage ?? e.message ?? L("זה לא הצליח. נסו שוב.")
            }
        }
        return L("אין חיבור. נסו שוב.")
    }
}

extension DarbAPI {
    /// A request to Darb's server as the signed-in person.
    static func authorized(_ path: String, method: String = "GET", body: Data? = nil) async throws -> (Data, Int) {
        guard let token = await Account.shared.token() else { throw URLError(.userAuthenticationRequired) }
        var req = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "content-type") }
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, res) = try await URLSession.shared.data(for: req)
        return (data, (res as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// admin/me's answer: 200 an admin, 403 signed in but not an admin, anything else unknown.
    static func adminStatus() async -> Int {
        (try? await authorized("admin/me"))?.1 ?? 0
    }
}
