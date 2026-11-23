import SafariServices
import SwiftUI
import UserNotifications

/// A web page to open inside the app.
struct WebPage: Identifiable {
    let url: URL
    var id: URL { url }
    init(_ url: URL) { self.url = url }
}

/// The system's in-app browser.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.dismissButtonStyle = .close
        return c
    }
    func updateUIViewController(_ c: SFSafariViewController, context: Context) {}
}

extension View {
    /// Opens a web page in the in-app browser when `page` is set.
    func webPage(_ page: Binding<WebPage?>) -> some View {
        sheet(item: page) { SafariView(url: $0.url).ignoresSafeArea() }
    }
}

/// "Tell me when it opens": one local notification at the place's next opening time.
enum Reminder {
    static func schedule(_ b: Business, at date: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = L("%@ נפתח", b.name)
        content.body = L("%lld דק׳ נסיעה מכאן.", b.minutes)
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id(b.id), content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        return (try? await center.add(request)) != nil
    }

    static func cancel(_ business: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(business)])
    }

    private static func id(_ business: Int) -> String { "opens-\(business)" }
}
