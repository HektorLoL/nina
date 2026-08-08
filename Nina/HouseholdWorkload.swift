import Foundation

struct HouseholdWorkloadEntry: Identifiable, Hashable {
    var name: String
    var tone: MemberTone
    var openCount: Int

    var id: String { name }
}

struct HouseholdWorkloadSnapshot: Hashable {
    var entries: [HouseholdWorkloadEntry]
    var sharedCount: Int
    var assignedCount: Int
    var isConclusive: Bool
    var isBalanced: Bool
    var leadName: String?
    var leadShare: Double
    var headline: String
    var message: String

    var maxOpenCount: Int {
        entries.map(\.openCount).max() ?? 0
    }

    var hasAnyLoad: Bool {
        assignedCount > 0 || sharedCount > 0
    }

    static let empty = HouseholdWorkloadSnapshot(
        entries: [],
        sharedCount: 0,
        assignedCount: 0,
        isConclusive: false,
        isBalanced: true,
        leadName: nil,
        leadShare: 0,
        headline: "Ainda sem retrato da casa",
        message: "A Nina precisa de algumas tarefas com responsável para desenhar a divisão sem chutar."
    )
}

enum HouseholdWorkload {
    static let sharedOwnerLabel = "Casa"

    // A split drawn from too few tasks reads as an accusation rather than a portrait.
    static let minimumAssignedSample = 6
    static let minimumCarriers = 2
    static let overloadShareThreshold = 0.6
    static let overloadLeadMargin = 3

    static func snapshot(
        tasks: [TaskItem],
        members: [HouseholdMember]
    ) -> HouseholdWorkloadSnapshot {
        let committedOpenTasks = tasks.filter { !$0.isDone && $0.kind == .task }

        var countsByKey: [String: Int] = [:]
        var displayNameByKey: [String: String] = [:]
        var sharedCount = 0

        for task in committedOpenTasks {
            let owner = task.owner.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !owner.isEmpty else {
                sharedCount += 1
                continue
            }

            let key = normalized(owner)
            guard key != normalized(sharedOwnerLabel) else {
                sharedCount += 1
                continue
            }

            countsByKey[key, default: 0] += 1
            if displayNameByKey[key] == nil {
                displayNameByKey[key] = owner
            }
        }

        let people = members.filter { $0.role != .assistant }
        var toneByKey: [String: MemberTone] = [:]
        var orderedKeys: [String] = []

        for person in people {
            let key = normalized(person.name)
            guard !key.isEmpty, toneByKey[key] == nil else { continue }
            toneByKey[key] = person.tone
            displayNameByKey[key] = person.name
            orderedKeys.append(key)
        }

        for key in countsByKey.keys.sorted() where toneByKey[key] == nil {
            toneByKey[key] = fallbackTone(for: key)
            orderedKeys.append(key)
        }

        let entries = orderedKeys.compactMap { key -> HouseholdWorkloadEntry? in
            let openCount = countsByKey[key] ?? 0
            guard let name = displayNameByKey[key], let tone = toneByKey[key] else { return nil }
            return HouseholdWorkloadEntry(name: name, tone: tone, openCount: openCount)
        }
        .sorted { left, right in
            left.openCount == right.openCount
                ? left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                : left.openCount > right.openCount
        }

        let assignedCount = entries.reduce(0) { $0 + $1.openCount }
        let carriers = entries.count { $0.openCount > 0 }
        let isConclusive = assignedCount >= minimumAssignedSample && carriers >= minimumCarriers

        guard isConclusive, let lead = entries.first, assignedCount > 0 else {
            return HouseholdWorkloadSnapshot(
                entries: entries,
                sharedCount: sharedCount,
                assignedCount: assignedCount,
                isConclusive: false,
                isBalanced: true,
                leadName: nil,
                leadShare: 0,
                headline: HouseholdWorkloadSnapshot.empty.headline,
                message: HouseholdWorkloadSnapshot.empty.message
            )
        }

        let runnerUpCount = entries.dropFirst().first?.openCount ?? 0
        let leadShare = Double(lead.openCount) / Double(assignedCount)
        let isBalanced = leadShare <= overloadShareThreshold
            || lead.openCount - runnerUpCount < overloadLeadMargin

        return HouseholdWorkloadSnapshot(
            entries: entries,
            sharedCount: sharedCount,
            assignedCount: assignedCount,
            isConclusive: true,
            isBalanced: isBalanced,
            leadName: lead.name,
            leadShare: leadShare,
            headline: isBalanced ? "Divisão equilibrada" : "Sinal de sobrecarga",
            message: isBalanced
                ? "As tarefas abertas estão bem distribuídas entre vocês. Nada para ajustar agora."
                : "\(lead.name) está com \(lead.openCount) das \(assignedCount) tarefas abertas. Um bom momento para conversar sobre a divisão."
        )
    }

    static func openTaskCount(for member: HouseholdMember, in tasks: [TaskItem]) -> Int {
        guard member.role != .assistant else { return 0 }
        let key = normalized(member.name)
        guard !key.isEmpty else { return 0 }
        return tasks.count { !$0.isDone && $0.kind == .task && normalized($0.owner) == key }
    }

    static func isSameOwner(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        return !left.isEmpty && left == normalized(rhs)
    }

    static func isSharedOwner(_ value: String) -> Bool {
        let owner = normalized(value)
        return owner.isEmpty || owner == normalized(sharedOwnerLabel)
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    private static func fallbackTone(for key: String) -> MemberTone {
        let tones = MemberTone.allCases
        let bucket = abs(key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 100_003 })
        return tones[bucket % tones.count]
    }
}
