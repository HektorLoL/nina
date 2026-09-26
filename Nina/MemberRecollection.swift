import Foundation

struct MemberRecollectionLine: Identifiable, Hashable {
    enum Source: Hashable {
        case memory(UUID)
        case routine(UUID)
    }

    let source: Source
    let text: String
    let isPrivate: Bool

    var id: Source { source }
}

struct MemberRecollectionSummary: Hashable {
    let name: String
    let memories: [MemberRecollectionLine]
    let routine: [MemberRecollectionLine]

    var lines: [MemberRecollectionLine] { memories + routine }

    var isEmpty: Bool { lines.isEmpty }

    var emptyLine: String { "A Nina aprende sobre \(name) nas conversas." }
}

enum MemberRecollection {
    static let memoryLineLimit = 3
    static let routineLineLimit = 3

    private static let particles: Set<String> = ["de", "da", "do", "das", "dos", "e"]

    private static let weeklyRhythms = [
        "todo domingo",
        "toda segunda",
        "toda terça",
        "toda quarta",
        "toda quinta",
        "toda sexta",
        "todo sábado"
    ]

    private struct Contender {
        let id: HouseholdMember.ID
        let key: [String]
    }

    static func replacesNote(for role: HouseholdRole) -> Bool {
        role == .child || role == .pet
    }

    // A child's or pet's note is never kept: nothing shows it, and a pet's would still reach the model.
    static func storedNote(_ typed: String, for role: HouseholdRole) -> String {
        replacesNote(for: role) ? "" : typed
    }

    // Built only from what this viewer can already read; a task's detail line can hold a document's reading and never appears.
    static func summary(
        for member: HouseholdMember,
        members: [HouseholdMember],
        memories: [NinaMemory],
        tasks: [TaskItem],
        viewerUserID: UUID?,
        calendar: Calendar = .current
    ) -> MemberRecollectionSummary {
        let name = distinguishingName(for: member, among: members)
        guard member.role != .assistant else {
            return MemberRecollectionSummary(name: name, memories: [], routine: [])
        }
        return MemberRecollectionSummary(
            name: name,
            memories: memoryLines(for: member, members: members, memories: memories, viewerUserID: viewerUserID),
            routine: routineLines(for: member, members: members, tasks: tasks, calendar: calendar)
        )
    }

    // Nina's row counts: a child who shares her name is never credited with what Nina's own memories say about herself.
    static func distinguishingName(for member: HouseholdMember, among members: [HouseholdMember]) -> String {
        let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return name }
        let others = members.filter { $0.id != member.id }.map { tokens($0.name) }
        for length in 1 ... words.count {
            let shown = words.prefix(length).joined(separator: " ")
            let prefix = tokens(shown)
            guard let last = prefix.last else { continue }
            if length < words.count, particles.contains(last) { continue }
            if !others.contains(where: { $0.starts(with: prefix) }) {
                return shown
            }
        }
        return name
    }

    // A name two people answer to credits nobody: naming the wrong person is worse than naming none.
    static func mentions(_ member: HouseholdMember, in text: String, among members: [HouseholdMember]) -> Bool {
        guard member.role != .assistant else { return false }
        let contenders = contenders(for: member, among: members)
        guard contenders.contains(where: { $0.id == member.id }) else { return false }
        return names(member.id, in: tokens(text), contenders: contenders)
    }

    static func rhythm(of task: TaskItem, calendar: Calendar = .current) -> String {
        let base = task.recurrence.title.lowercased()
        guard let dueAt = task.dueAt else { return base }
        switch task.recurrence {
        case .daily:
            return "\(base), \(formatted(dueAt, "HH:mm", calendar: calendar))"
        case .weekly:
            let index = calendar.component(.weekday, from: dueAt) - 1
            let day = weeklyRhythms.indices.contains(index) ? weeklyRhythms[index] : base
            return "\(day), \(formatted(dueAt, "HH:mm", calendar: calendar))"
        case .monthly:
            return "\(base), dia \(calendar.component(.day, from: dueAt))"
        case .yearly:
            return "\(base), \(formatted(dueAt, "d 'de' MMMM", calendar: calendar))"
        case .none:
            return base
        }
    }

    private static func memoryLines(
        for member: HouseholdMember,
        members: [HouseholdMember],
        memories: [NinaMemory],
        viewerUserID: UUID?
    ) -> [MemberRecollectionLine] {
        let contenders = contenders(for: member, among: members)
        guard contenders.contains(where: { $0.id == member.id }) else { return [] }
        return memories
            .filter { isVisible($0, to: viewerUserID) && !flattened($0.title).isEmpty }
            .filter {
                names(member.id, in: tokens($0.title), contenders: contenders)
                    || names(member.id, in: tokens($0.body), contenders: contenders)
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(memoryLineLimit)
            .map { memory in
                MemberRecollectionLine(
                    source: .memory(memory.id),
                    text: flattened(memory.title),
                    isPrivate: memory.visibility == .privateMemory
                )
            }
    }

    private static func routineLines(
        for member: HouseholdMember,
        members: [HouseholdMember],
        tasks: [TaskItem],
        calendar: Calendar
    ) -> [MemberRecollectionLine] {
        HouseholdWorkload.assignedTasks(to: member, in: tasks, members: members)
            .filter { task in
                task.kind == .task
                    && !task.isDone
                    && task.recurrence != .none
                    && !ChildDay.title(of: task).isEmpty
            }
            .sorted { lhs, rhs in
                let left = routineKey(of: lhs, calendar: calendar)
                let right = routineKey(of: rhs, calendar: calendar)
                if left != right { return left.lexicographicallyPrecedes(right) }
                let byTitle = ChildDay.title(of: lhs).localizedStandardCompare(ChildDay.title(of: rhs))
                if byTitle != .orderedSame { return byTitle == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(routineLineLimit)
            .map { task in
                MemberRecollectionLine(
                    source: .routine(task.id),
                    text: "\(ChildDay.title(of: task)) · \(rhythm(of: task, calendar: calendar))",
                    isPrivate: false
                )
            }
    }

    private static func routineKey(of task: TaskItem, calendar: Calendar) -> [Int] {
        let rank: Int
        switch task.recurrence {
        case .daily: rank = 0
        case .weekly: rank = 1
        case .monthly: rank = 2
        case .yearly: rank = 3
        case .none: rank = 4
        }
        guard let dueAt = task.dueAt else { return [rank, 1] }
        let parts = calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: dueAt)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        switch task.recurrence {
        case .daily:
            return [rank, 0, minute]
        case .weekly:
            return [rank, 0, ((parts.weekday ?? 1) + 5) % 7, minute]
        case .monthly:
            return [rank, 0, parts.day ?? 0, minute]
        case .yearly:
            return [rank, 0, parts.month ?? 0, parts.day ?? 0, minute]
        case .none:
            return [rank, 0]
        }
    }

    // Every longer run of a full name is also a key, so the father "João Pedro Silva" keeps "João Pedro" from his son Pedro.
    private static func contenders(
        for member: HouseholdMember,
        among members: [HouseholdMember]
    ) -> [Contender] {
        let pool = members.contains { $0.id == member.id } ? members : members + [member]
        return pool
            .flatMap { person -> [Contender] in
                let fullName = tokens(person.name)
                guard !fullName.isEmpty else { return [] }
                let shortest = tokens(distinguishingName(for: person, among: pool)).count
                let first = min(max(shortest, 1), fullName.count)
                return (first ... fullName.count).map { length in
                    Contender(id: person.id, key: Array(fullName.prefix(length)))
                }
            }
            .filter { $0.key.joined().count >= 2 }
    }

    private static func names(
        _ memberID: HouseholdMember.ID,
        in words: [String],
        contenders: [Contender]
    ) -> Bool {
        var index = 0
        while index < words.count {
            let matching = contenders.filter { contender in
                let end = index + contender.key.count
                return end <= words.count && Array(words[index ..< end]) == contender.key
            }
            guard let longest = matching.map(\.key.count).max() else {
                index += 1
                continue
            }
            let winners = matching.filter { $0.key.count == longest }
            if winners.count == 1, winners.first?.id == memberID { return true }
            index += longest
        }
        return false
    }

    private static func isVisible(_ memory: NinaMemory, to viewerUserID: UUID?) -> Bool {
        switch memory.visibility {
        case .shared:
            true
        case .privateMemory:
            viewerUserID != nil && memory.ownerUserID == viewerUserID
        }
    }

    private static func tokens(_ value: String) -> [String] {
        HouseholdWorkload.normalized(value)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func flattened(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatted(_ date: Date, _ format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
