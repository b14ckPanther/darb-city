import ActivityKit
import CoreLocation
import Foundation

/// Starts and tidies the drive's Live Activity. One drive at a time: a new one replaces the last. The drive happens
/// in another app (Waze, Maps), so Darb follows the phone's location in the background while the drive lasts, and
/// ends the activity on arrival: within a short walk of the place, or well after the time it should have taken.
@MainActor
enum DriveLive {
    /// Close enough to count as there.
    static let arrivedWithin: CLLocationDistance = 150
    /// How long past the expected arrival a drive is given before it ends anyway.
    static let grace: TimeInterval = 30 * 60

    private static var watch: Task<Void, Never>?
    private static var session: CLBackgroundActivitySession?

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
        follow(to: CLLocation(latitude: b.lat, longitude: b.lng), until: arrive.addingTimeInterval(grace))
    }

    /// Watches the way there. Started while the app is in front (the tap on Navigate), so the background session may
    /// keep it going while the navigation app is on screen; it stops itself on arrival or at `until`.
    private static func follow(to place: CLLocation, until: Date) {
        watch?.cancel()
        session?.invalidate()
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        session = CLBackgroundActivitySession()
        watch = Task {
            var startedFar: Bool?
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    if Task.isCancelled || Date.now > until { break }
                    guard let here = update.location, here.horizontalAccuracy >= 0, here.horizontalAccuracy < 200 else { continue }
                    let left = here.distance(from: place)
                    // a drive started right next to the place ends by the clock, not on the first fix
                    if startedFar == nil { startedFar = left > arrivedWithin * 2 }
                    if startedFar == true, left <= arrivedWithin { break }
                }
            } catch {}
            guard !Task.isCancelled else { return }
            for a in Activity<DriveAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            session?.invalidate()
            session = nil
        }
    }

    /// Ends drives that are long over, when the app comes back.
    static func tidy() {
        Task {
            if Activity<DriveAttributes>.activities.isEmpty { watch?.cancel(); session?.invalidate(); session = nil }
            for a in Activity<DriveAttributes>.activities where (a.content.staleDate ?? .distantFuture) < .now {
                await a.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
