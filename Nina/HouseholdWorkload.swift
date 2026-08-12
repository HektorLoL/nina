import Foundation

// A qualitative band, never a quantity. A number lets two people compare
// themselves against each other, which is the thing the portrait exists to avoid.
enum WorkloadBand: Int, Hashable {
    case light = 0
    case similar = 1
    case heavier = 2

    var title: String {
        switch self {
        case .light: "leve"
        case .similar: "parecido"
        case .heavier: "mais pesado"
        }
    }
}

struct HouseholdWorkloadEntry: Identifiable, Hashable {
    var memberID: UUID?
    var name: String
    var tone: MemberTone
    // Never rendered. It exists to compute the band and to answer per-member
    // queries; putting it on screen would restore the scoreboard.
    var openCount: Int
    var band: WorkloadBand = .similar
    var isShared: Bool = false

    var id: String { memberID?.uuidString ?? "label:\(name)" }
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
        message: "Preciso de algumas tarefas com dono para desenhar a divisão sem chutar. E não desenho nenhum gráfico até lá."
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
        let people = members.filter { $0.role != .assistant }
        let resolver = TaskOwnerResolver(people: people)
        let committedOpenTasks = tasks.filter { !$0.isDone && $0.kind == .task }

        var countsByOwner: [TaskOwnerBucket: Int] = [:]
        var labelDisplayNames: [String: String] = [:]
        var sharedCount = 0

        for task in committedOpenTasks {
            switch resolver.bucket(of: task) {
            case .shared:
                sharedCount += 1
            case .member(let memberID):
                countsByOwner[.member(memberID), default: 0] += 1
            case .label(let key):
                countsByOwner[.label(key), default: 0] += 1
                if labelDisplayNames[key] == nil {
                    labelDisplayNames[key] = task.owner.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        var entries = people.map { person in
            HouseholdWorkloadEntry(
                memberID: person.id,
                name: resolver.displayName(for: person),
                tone: person.tone,
                openCount: countsByOwner[.member(person.id)] ?? 0
            )
        }

        for key in labelDisplayNames.keys.sorted() {
            entries.append(
                HouseholdWorkloadEntry(
                    memberID: nil,
                    name: labelDisplayNames[key] ?? key,
                    tone: fallbackTone(for: key),
                    openCount: countsByOwner[.label(key)] ?? 0
                )
            )
        }

        // Household order, never sorted by load. Row order is an encoding, and
        // sorting descending *is* the ranking the caption disclaims.
        let assignedCount = entries.reduce(0) { $0 + $1.openCount }
        let carriers = entries.count { $0.openCount > 0 }
        let isConclusive = assignedCount >= minimumAssignedSample && carriers >= minimumCarriers

        if carriers > 0 {
            let average = Double(assignedCount) / Double(carriers)
            for index in entries.indices {
                entries[index].band = band(for: entries[index].openCount, average: average)
            }
        }

        // Unassigned work is credited to the house and never to a person.
        if sharedCount > 0 {
            entries.append(
                HouseholdWorkloadEntry(
                    memberID: nil,
                    name: sharedOwnerLabel,
                    tone: .lavender,
                    openCount: sharedCount,
                    band: .similar,
                    isShared: true
                )
            )
        }

        let ranked = entries.filter { !$0.isShared }.max { $0.openCount < $1.openCount }

        guard isConclusive, let lead = ranked, assignedCount > 0 else {
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

        let runnerUpCount = entries
            .filter { !$0.isShared && $0.memberID != lead.memberID }
            .map(\.openCount)
            .max() ?? 0
        let leadShare = Double(lead.openCount) / Double(assignedCount)
        let isBalanced = leadShare <= overloadShareThreshold
            || lead.openCount - runnerUpCount < overloadLeadMargin

        // The message carries no count and no percentage, for the same reason the
        // chart does not: a quantified comparison between two people is a
        // scoreboard whatever the caption says.
        return HouseholdWorkloadSnapshot(
            entries: entries,
            sharedCount: sharedCount,
            assignedCount: assignedCount,
            isConclusive: true,
            isBalanced: isBalanced,
            leadName: lead.name,
            leadShare: leadShare,
            headline: isBalanced ? "A casa está parecida" : "Sinal de sobrecarga",
            message: isBalanced
                ? "O que está aberto agora está bem dividido entre vocês. Nada para ajustar."
                : "\(lead.name) está com a parte mais pesada do que está aberto agora. Pode ser uma boa hora para conversar."
        )
    }

    private static func band(for count: Int, average: Double) -> WorkloadBand {
        guard average > 0 else { return .similar }
        let ratio = Double(count) / average
        if ratio >= 1.25 { return .heavier }
        if ratio <= 0.75 { return .light }
        return .similar
    }

    static func openTaskCount(
        for member: HouseholdMember,
        in tasks: [TaskItem],
        members: [HouseholdMember]
    ) -> Int {
        guard member.role != .assistant else { return 0 }
        let resolver = TaskOwnerResolver(people: members.filter { $0.role != .assistant })
        return tasks.count { task in
            guard !task.isDone, task.kind == .task else { return false }
            return resolver.bucket(of: task) == .member(member.id)
        }
    }

    static func isSameOwner(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalized(lhs)
        return !left.isEmpty && left == normalized(rhs)
    }

    static func isSharedOwner(_ value: String) -> Bool {
        let owner = normalized(value)
        return owner.isEmpty || owner == normalized(sharedOwnerLabel)
    }

    fileprivate static func normalized(_ value: String) -> String {
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

private enum TaskOwnerBucket: Hashable {
    case shared
    case member(UUID)
    case label(String)
}

private struct TaskOwnerResolver {
    private let peopleByID: [UUID: HouseholdMember]
    private let memberIDsByName: [String: [UUID]]

    init(people: [HouseholdMember]) {
        peopleByID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        memberIDsByName = Dictionary(grouping: people, by: { HouseholdWorkload.normalized($0.name) })
            .mapValues { $0.map(\.id) }
    }

    // Two people answering to the same name resolve to nobody: naming the wrong person is worse
    // than leaving the work unattributed.
    func bucket(of task: TaskItem) -> TaskOwnerBucket {
        guard !HouseholdWorkload.isSharedOwner(task.owner) else { return .shared }

        if let memberID = task.ownerMemberID, peopleByID[memberID] != nil {
            return .member(memberID)
        }

        let key = HouseholdWorkload.normalized(task.owner)
        if let memberIDs = memberIDsByName[key], memberIDs.count == 1, let memberID = memberIDs.first {
            return .member(memberID)
        }
        return .label(key)
    }

    func displayName(for member: HouseholdMember) -> String {
        let relationship = member.relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        let namesakes = memberIDsByName[HouseholdWorkload.normalized(member.name)]?.count ?? 1
        guard namesakes > 1, !relationship.isEmpty else { return member.name }
        return "\(member.name) · \(relationship)"
    }
}
