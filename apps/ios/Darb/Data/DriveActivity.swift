import ActivityKit
import AppIntents
import Foundation

/// The drive to a place, on the Lock Screen and in the Dynamic Island: what it is, how long until you get there,
/// and until when it is open. Started when the way is handed to the navigation app. Shared by the app and the widget.
struct DriveAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When you get there, at the time the drive started.
        var arrive: Date
        /// Whether it is open and until when, in the person's language.
        var until: String
        var open: Bool
    }
    var name: String
    /// The place's object, as named in the widget's small art.
    var art: String
    /// The need's colour, for the disc behind the object.
    var hex: UInt32
    var rtl: Bool
}

/// "I'm here", from the Lock Screen or the Dynamic Island: ends the drive. Runs in the app, woken in the background.
struct EndDriveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End the drive"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        for a in Activity<DriveAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        return .result()
    }
}
