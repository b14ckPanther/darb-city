import SwiftUI
import UIKit
import UserNotifications

/// The settings: language, where you are, how the app looks, reminders and the navigation app,
/// and the ways on to what you kept, to Darb's own pages and to the small print.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @Binding var path: [MenuPage]
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var nav = NavApp.preferred
    @State private var kept = SettingsView.size()
    @State private var cleared = false
    @State private var confirmClear = false

    static func size() -> String { ByteCountFormatter.string(fromByteCount: ImageStore.bytes(), countStyle: .file) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                GroupTitle(L("web.messages.language"))
                LanguageSwitch()

                GroupTitle(L("ישוב ומיקום"))
                RowGroup {
                    link(.town, store.isLive ? "location.fill" : "mappin.and.ellipse", L("ליד %@", store.homeName),
                         store.isLive ? L("לפי המיקום שלכם") : L("לפי ישוב שבחרתם"))
                }

                GroupTitle(L("מראה"))
                Segments(options: [(value: Appearance.hour, title: L("לפי השעה"), font: nil), (value: .light, title: L("בהיר"), font: nil), (value: .dark, title: L("כהה"), font: nil)],
                         selection: Binding(get: { store.appearance }, set: { store.setAppearance($0) }))
                Text(L("לפי השעה: נייר ביום, דיו בלילה.")).font(.darb(.caption)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)

                GroupTitle(L("התראות"))
                RowGroup {
                    MenuRow(symbol: "bell.fill", title: L("להודיע לי כשמקום נפתח"), detail: notificationLine) {
                        switch notifications {
                        case .authorized, .provisional, .ephemeral:
                            Text(L("פעיל")).font(.darb(.footnote, .bold)).foregroundStyle(Color.open)
                        case .denied:
                            pill(L("הגדרות")) { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                        default:
                            pill(L("לאפשר")) { Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]); await read() } }
                        }
                    }
                    if !store.reminders.isEmpty {
                        MenuRow(symbol: "clock.fill", title: L("תזכורות ממתינות: %lld", store.reminders.count), detail: nil) {
                            pill(L("לבטל הכול")) {
                                for id in store.reminders { Reminder.cancel(id); store.setReminder(id, on: false) }
                            }
                        }
                    }
                }

                GroupTitle(L("ניווט"))
                RowGroup {
                    ForEach(NavApp.installed) { app in
                        Button { nav = app; NavApp.preferred = app; Haptic.tap() } label: {
                            MenuRow(symbol: app.symbol, title: app.title, detail: nil) {
                                if nav == app { Image(systemName: "checkmark").font(.symbol(.subheadline)) }
                            }
                        }
                        .buttonStyle(PressStyle(scale: 0.985))
                        .accessibilityAddTraits(nav == app ? .isSelected : [])
                    }
                }
                Text(L("כפתור הניווט פותח את האפליקציה הזו. מוצגות רק אפליקציות שמותקנות במכשיר.")).font(.darb(.caption)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)

                GroupTitle(L("אחסון"))
                RowGroup {
                    MenuRow(symbol: "photo.stack.fill", title: L("תמונות שמורות"),
                            detail: L("%@ בטלפון, כדי שהחנויות ייפתחו מיד, גם בלי קליטה", kept)) {
                        if cleared { Image(systemName: "checkmark").font(.symbol(.subheadline)).foregroundStyle(Color.open) }
                        else { pill(L("לנקות")) { confirmClear = true } }
                    }
                }
                .confirmationDialog(L("לנקות את התמונות השמורות?"), isPresented: $confirmClear, titleVisibility: .visible) {
                    Button(L("לנקות"), role: .destructive) {
                        ImageStore.clear(); Haptic.done()
                        withAnimation(.snappy) { cleared = true; kept = Self.size() }
                    }
                } message: {
                    Text(L("הן יורדו שוב בפעם הבאה שתפתחו חנות."))
                }

                GroupTitle(L("עוד"))
                RowGroup {
                    link(.saved, "bookmark.fill", L("מקומות ששמרתי"), store.saved.isEmpty ? nil : L("%lld מקומות", store.saved.count))
                    link(.about, "signpost.right.fill", L("על דרב"), nil)
                    link(.contact(topic: .general, plan: nil), "envelope.fill", L("web.messages.contactUs"), nil)
                    link(.legal(.terms), "doc.text.fill", L("תנאי שימוש"), nil)
                    link(.legal(.privacy), "hand.raised.fill", L("פרטיות"), nil)
                    MenuRow(symbol: "number", title: L("גרסה"), detail: nil) {
                        Text(verbatim: Bundle.main.version).font(.figure(.subheadline, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 4)
        }
        .page(L("הגדרות"))
        .task { await read() }
        .onChange(of: phase) { _, p in if p == .active { Task { await read() } } }
    }

    private var notificationLine: String {
        switch notifications {
        case .denied: L("ההתראות כבויות בהגדרות המכשיר")
        case .authorized, .provisional, .ephemeral: L("בעמוד של מקום סגור, הפעמון מזכיר כשהוא נפתח")
        default: L("רק כשתבקשו, ורק למקום שביקשתם")
        }
    }

    private func read() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func link(_ page: MenuPage, _ symbol: String, _ title: String, _ detail: String?) -> some View {
        Button { path.append(page) } label: { MenuRow(symbol: symbol, title: title, detail: detail) }
            .buttonStyle(PressStyle(scale: 0.985))
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.darb(.footnote, .bold)).padding(.horizontal, 12).frame(height: 32).background(Color.card2, in: Capsule())
                .frame(height: 44).contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.95))
    }
}
