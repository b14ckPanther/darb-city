import AppIntents

/// The nine everyday needs, as Siri and Shortcuts offer them.
enum NeedChoice: String, AppEnum {
    case food, sweets, coffee, bakery, pharmacy, grocery, fuel, garage, bank

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "מה מחפשים"
    static let caseDisplayRepresentations: [NeedChoice: DisplayRepresentation] = [
        .food: "אוכל", .sweets: "מתוקים", .coffee: "קפה", .bakery: "מאפייה", .pharmacy: "בית מרקחת",
        .grocery: "מכולת", .fuel: "דלק", .garage: "מוסך", .bank: "בנק",
    ]
}

/// "What's open now": the nearest open place for one need, or for the three that lead at this hour.
struct WhatsOpenIntent: AppIntent {
    static let title: LocalizedStringResource = "מה פתוח לידי"
    static let description = IntentDescription("המקום הפתוח הקרוב ביותר, לפי מה שמחפשים.")

    @Parameter(title: "מה מחפשים")
    var need: NeedChoice?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Lang.reload()
        guard let data = Nearest.load() else { return .result(dialog: IntentDialog(stringLiteral: L("לא הצלחתי לקרוא את הנתונים של דרב."))) }
        // from where the app last stood: the person's position, or the town they chose
        let all = Nearest.answers(in: data, from: Nearest.origin(in: data).point, at: .now)
        let picked = need.map { n in all.filter { $0.need.key == n.rawValue } } ?? Array(all.filter { $0.status.isOpen }.prefix(3))
        guard !picked.isEmpty else { return .result(dialog: IntentDialog(stringLiteral: L("לא מצאתי מקום פתוח במרחק נסיעה."))) }
        let lines = picked.map { a in
            a.status.isOpen
                ? L("%@: %@, %lld דקות נסיעה, %@.", a.need.title, a.business.name, a.business.minutes, a.status.text)
                : L("%@: הכי קרוב זה %@, %@.", a.need.title, a.business.name, a.status.text)
        }
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: " ")))
    }
}

/// The phrases that reach Darb from Siri and Spotlight without any setup.
struct DarbShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WhatsOpenIntent(),
            phrases: ["מה פתוח עכשיו ב\(.applicationName)", "\(.applicationName), מה פתוח עכשיו", "מה פתוח עכשיו לפי \(.applicationName)"],
            shortTitle: "מה פתוח לידי",
            systemImageName: "location.fill"
        )
    }
}
