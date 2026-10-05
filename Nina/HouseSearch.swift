import Foundation

// "remedio" finds "Remédio": a search folds accents and case the way people type on a phone keyboard.
enum HouseSearch {
    static func matches(_ text: String, query: String) -> Bool {
        let needle = fold(query)
        guard !needle.isEmpty else { return false }
        return fold(text).contains(needle)
    }

    static func tasks(_ tasks: [TaskItem], query: String) -> [TaskItem] {
        tasks.filter { matches($0.title, query: query) || matches($0.subtitle, query: query) }
    }

    static func shoppingItems(_ items: [ShoppingItem], query: String) -> [ShoppingItem] {
        items.filter { matches($0.title, query: query) || matches($0.amount, query: query) }
    }

    // A proposal that repeats something still open is flagged, never blocked: the person decides if it is a second one.
    static func openTwin(
        of payload: NinaProposalPayload,
        kind: NinaProposalKind,
        tasks: [TaskItem],
        shoppingItems: [ShoppingItem]
    ) -> Bool {
        let title = fold(payload.title)
        guard !title.isEmpty else { return false }
        switch kind {
        case .shopping:
            return shoppingItems.contains { !$0.isChecked && fold($0.title) == title }
        case .memory:
            return false
        case .task, .reminder, .seed:
            return tasks.contains { !$0.isDone && fold($0.title) == title }
        }
    }

    private static func fold(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "pt_BR"))
    }
}
