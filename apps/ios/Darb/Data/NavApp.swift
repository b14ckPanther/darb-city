import Foundation
import UIKit

/// The app the way is handed to. Only the ones on this phone are offered.
enum NavApp: String, CaseIterable, Sendable, Identifiable {
    case waze, apple, google

    var id: String { rawValue }
    /// Product names are the same in every language.
    var title: String {
        switch self {
        case .waze: "Waze"
        case .apple: "Apple Maps"
        case .google: "Google Maps"
        }
    }
    var symbol: String {
        switch self {
        case .waze: "location.fill"
        case .apple: "map.fill"
        case .google: "mappin.and.ellipse"
        }
    }
    /// The scheme that tells whether the app is on the phone.
    private var probe: String {
        switch self {
        case .waze: "waze://"
        case .apple: "maps://"
        case .google: "comgooglemaps://"
        }
    }

    @MainActor var isInstalled: Bool { URL(string: probe).map(UIApplication.shared.canOpenURL) ?? false }
    /// Asking the phone which apps it has is slow enough to feel, so the answer is kept for a minute.
    @MainActor private static var known: (apps: [NavApp], at: Date)?
    @MainActor static var installed: [NavApp] {
        if let k = known, Date.now.timeIntervalSince(k.at) < 60 { return k.apps }
        let found = allCases.filter(\.isInstalled)
        let apps = found.isEmpty ? [.apple] : found
        known = (apps, .now)
        return apps
    }

    /// The link that starts a drive to a point in this app.
    func drive(lat: Double, lng: Double) -> URL {
        switch self {
        case .waze: URL(string: "https://waze.com/ul?ll=\(lat),\(lng)&navigate=yes")!
        case .apple: URL(string: "https://maps.apple.com/?daddr=\(lat),\(lng)&dirflg=d")!
        case .google: URL(string: "comgooglemaps://?daddr=\(lat),\(lng)&directionsmode=driving")!
        }
    }

    private static let key = "darbNavApp"
    /// The app the person chose, when it is still on the phone; else Waze, else whatever is there.
    @MainActor static var preferred: NavApp {
        get {
            let all = installed
            if let saved = UserDefaults.standard.string(forKey: key).flatMap(NavApp.init(rawValue:)), all.contains(saved) { return saved }
            return all.contains(.waze) ? .waze : all[0]
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Opening the outside world: the way there, a phone call, a message.
enum Outside {
    /// The way to a business, in the navigation app the person uses.
    @MainActor static func way(_ b: Business) -> URL { NavApp.preferred.drive(lat: b.lat, lng: b.lng) }
    /// A link to a place that opens anywhere, for sharing with somebody else.
    static func shareLink(_ b: Business) -> URL { URL(string: "https://maps.apple.com/?ll=\(b.lat),\(b.lng)&q=\(b.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")! }
    static func phone(_ p: String) -> URL? { URL(string: "tel:" + p.filter { $0.isNumber || $0 == "+" }) }
    static func whatsapp(_ p: String) -> URL? { URL(string: "https://wa.me/" + p.filter(\.isNumber)) }
    /// The question to send before driving to a place whose hours are not its own.
    static var question: String { L("היי, ראיתי אתכם בדרב. אתם פתוחים עכשיו?") }
    /// WhatsApp with the question already written.
    static func ask(_ p: String) -> URL? {
        var c = URLComponents(string: "https://wa.me/" + p.filter(\.isNumber))
        c?.queryItems = [URLQueryItem(name: "text", value: question)]
        return c?.url
    }
    /// A phone number the way people say it, in groups with spaces.
    static func display(_ p: String) -> String {
        p.replacingOccurrences(of: "+972 ", with: "0").replacingOccurrences(of: "-", with: " ")
    }
}
