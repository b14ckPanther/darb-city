import Foundation
import os

/// Timing, for keeping the app quick. Every measure is a signpost (Instruments, Points of Interest), and with
/// `-darbPerf YES` it is also printed, so a run on a phone can be read from the console:
///   PERF work  store.measure  12.4 ms
///   PERF shown need           83.0 ms     (from the tap to the first frame of what it opened)
enum Perf {
    private static let poi = OSSignposter(subsystem: "il.co.darb.app", category: .pointsOfInterest)
    static let prints = UserDefaults.standard.bool(forKey: "darbPerf")
    nonisolated(unsafe) private static var taps: [String: (at: DispatchTime, state: OSSignpostIntervalState)] = [:]

    /// Runs a piece of work and says how long it took.
    @discardableResult static func time<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = poi.beginInterval(name)
        let start = DispatchTime.now()
        defer {
            poi.endInterval(name, state)
            if prints { say("PERF work  \(name)  \(ms(since: start)) ms") }
        }
        return try work()
    }

    /// The person touched something that opens a screen.
    @MainActor static func tap(_ what: String) {
        taps[what] = (.now(), poi.beginInterval("tap to frame", "\(what)"))
    }

    /// The screen it opened is on. The time is taken once its first frame has been handed over.
    @MainActor static func shown(_ what: String) {
        guard let tap = taps.removeValue(forKey: what) else { return }
        let built = ms(since: tap.at)
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                poi.endInterval("tap to frame", tap.state)
                if prints { say("PERF shown \(what)  \(ms(since: tap.at)) ms  (built in \(built))") }
            }
        }
    }

    private static let log = Logger(subsystem: "il.co.darb.app", category: "perf")
    /// Printed and flushed at once, so a run on a phone can be read as it happens; and logged, for Console.
    private static func say(_ line: String) {
        print(line)
        fflush(stdout)
        log.notice("\(line, privacy: .public)")
        // also kept in a file in the app's documents, to read back from a phone
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("perf.log"),
              let data = (line + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: url) }
    }

    /// With `-darbPerf YES`: watches the main thread and reports every time it was stuck for more than 80 ms,
    /// which is what a person feels as a tap that does nothing.
    static func watchMainThread() {
        guard prints else { return }
        Thread.detachNewThread {
            while true {
                let sent = DispatchTime.now()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { done.signal() }
                done.wait()
                let waited = Double(DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds) / 1_000_000
                if waited > 80 { say(String(format: "PERF stall main thread %.0f ms", waited)) }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    private static func ms(since start: DispatchTime) -> String {
        String(format: "%.1f", Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
}
