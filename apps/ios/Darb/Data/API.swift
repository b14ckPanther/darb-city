import Foundation

/// The Darb API, the same one the website talks to (packages/contracts). The app sends it two things:
/// a message from the contact form, and a request to add a business.
enum DarbAPI {
    /// `-darbAPI http://localhost:8787` points the app at another server, for tests.
    static var base: URL {
        UserDefaults.standard.string(forKey: "darbAPI").flatMap(URL.init(string:)) ?? URL(string: "https://api.darb.co.il")!
    }
    /// Where a message goes when the API cannot be reached.
    static let email = "founder@darb.co.il"
    static let instagram = URL(string: "https://www.instagram.com/darbco/")!

    enum Failure: Error, Equatable {
        /// Too many messages from here; try again in a while.
        case tooMany
        /// The server did not accept what was sent.
        case rejected
        /// No connection, or the server did not answer.
        case unreachable
    }

    /// The contact form, as `InquiryCreateSchema` reads it.
    struct Inquiry: Encodable, Equatable {
        enum Topic: String, Encodable, CaseIterable, Sendable { case general, join, plan, other }
        var name: String
        var contact: String
        var businessName: String?
        var topic: Topic
        var plan: String?
        var message: String
        var locale: String

        /// What is wrong with the form, by field; empty when it can be sent. The same rules as the contract.
        func problems() -> Set<Field> {
            var out: Set<Field> = []
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.count < 2 || n.count > 80 { out.insert(.name) }
            let c = contact.trimmingCharacters(in: .whitespacesAndNewlines)
            if c.count < 5 || c.count > 120 || !(Check.email(c) || Check.phone(c)) { out.insert(.contact) }
            let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if m.count < 10 { out.insert(.messageShort) } else if m.count > 3000 { out.insert(.messageLong) }
            return out
        }
        enum Field: Sendable { case name, contact, messageShort, messageLong }
    }

    /// The join form, as `JoinCreateSchema` reads it.
    struct Join: Encodable {
        struct Owner: Encodable { var name: String; var phone: String; var email: String? }
        struct Interval: Encodable, Equatable { var open: String; var close: String }
        struct Week: Encodable { var weekly: [String: [Interval]]; var exceptions: [String] = [] }
        var name: [String: String]
        var kindSlug: String
        var placeSlug: String
        var lat: Double
        var lng: Double
        var address: [String: String]
        var phone: String?
        var whatsapp: String?
        var website: String?
        var links: [String: String]
        var hours: Week
        var description: [String: String]
        var owner: Owner
        var note: String?
        var source = "manual"
        var locale: String
    }

    enum Check {
        static func email(_ s: String) -> Bool { s.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]{2,}/) != nil }
        /// A phone number: digits with spaces, dashes and brackets, an optional +, at least 7 digits.
        static func phone(_ s: String) -> Bool {
            s.wholeMatch(of: /\+?[0-9 ()\-]+/) != nil && s.filter(\.isNumber).count >= 7
        }
        /// The stricter phone the join form asks for.
        static func joinPhone(_ s: String) -> Bool { s.wholeMatch(of: /\+?[0-9][0-9 ()\-]{5,19}/) != nil }
    }

    static func send(_ inquiry: Inquiry) async throws(Failure) { try await post("inquiries", inquiry) }
    static func send(_ join: Join) async throws(Failure) { try await post("join", join) }

    private static func post(_ path: String, _ body: some Encodable) async throws(Failure) {
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.httpBody = try? JSONEncoder().encode(body)
        let status: Int
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw .unreachable
        }
        switch status {
        case 200...299: return
        case 429: throw .tooMany
        case 400...499: throw .rejected
        default: throw .unreachable
        }
    }

    /// A ready email with the same message, for when the API cannot be reached.
    static func mail(subject: String, body: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = email
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return c.url
    }
}
