import CoreMotion
import SwiftUI

/// How far the phone leans from where it was held when the app opened, smoothed and clamped to −1…1.
/// One shared motion manager, started on first use and only while something on screen asks for it.
@MainActor @Observable
final class MotionTilt {
    static let shared = MotionTilt()
    private(set) var roll: Double = 0
    private(set) var pitch: Double = 0
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var base: (roll: Double, pitch: Double)?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 20
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            MainActor.assumeIsolated {
                if self.base == nil { self.base = (a.roll, a.pitch) }
                let r = max(-1, min(1, (a.roll - self.base!.roll) / 0.5))
                let p = max(-1, min(1, (a.pitch - self.base!.pitch) / 0.5))
                // a phone held still, or lying on a table, changes nothing: no update, and nothing is redrawn
                guard abs(r - self.roll) > 0.03 || abs(p - self.pitch) > 0.03 else { return }
                withAnimation(.interpolatingSpring(stiffness: 60, damping: 14)) {
                    self.roll = self.roll * 0.6 + r * 0.4
                    self.pitch = self.pitch * 0.6 + p * 0.4
                }
            }
        }
    }
}
