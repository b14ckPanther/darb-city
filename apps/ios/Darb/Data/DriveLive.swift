import ActivityKit
import Foundation

/// Starts and tidies the drive's Live Activity. One drive at a time: a new one replaces the last.
@MainActor
enum DriveLive {
    static func start(_ e: Entry, store: Store) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let b = e.business
        let need = Need.forKind(b.kind)
        let arrive = Date.now.addingTimeInterval(Double(max(1, b.minutes)) * 60)
        let state = DriveAttributes.ContentState(arrive: arrive, until: e.status.text, open: e.status.isOpen)
        let attrs = DriveAttributes(name: b.name, art: store.art(for: b).render ?? need?.art ?? "p-plate",
                                    hex: need?.hex ?? 0xFFC330, rtl: store.lang.isRTL)
        Task {
            for a in Activity<DriveAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            // ten minutes after the expected arrival it is stale, and it leaves when the app next opens
            _ = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: arrive.addingTimeInterval(600)))
        }
    }

    /// Ends drives that are long over, when the app comes back.
    static func tidy() {
        Task {
            for a in Activity<DriveAttributes>.activities where (a.content.staleDate ?? .distantFuture) < .now {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
