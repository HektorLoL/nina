import Foundation

// No field for the task's detail: it can hold a document's reading, and rows reach a child, a printer and a chat.
struct ChildDayRow: Identifiable, Hashable {
    enum State: Hashable { case open, doneHere, doneElsewhere }

    let id: TaskItem.ID
    let title: String
    let time: String?
    let symbolName: String
    let state: State

    var isDone: Bool { state != .open }
}

struct ChildDayMark: Equatable {
    let baseline: TaskItem
    let written: TaskItem
    let markedAt: Date

    // A mark undoes only its own tap: once anyone else moves the task, it undoes nothing.
    func holds(on live: TaskItem) -> Bool {
        live.id == written.id
            && live.kind == .task
            && live.isDone == written.isDone
            && Self.isSameSecond(live.dueAt, written.dueAt)
            && Self.isSameSecond(live.snoozedUntil, written.snoozedUntil)
    }

    private static func isSameSecond(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): abs(lhs.timeIntervalSince(rhs)) < 1
        default: false
        }
    }
}

enum ChildDayTap: Equatable {
    case markDone(TaskItem.ID)
    case reopen(ChildDayMark)
    case ignore
}

enum ChildDay {
    static let rowsPerPrintedPage = 10

    // A list that leaves the phone must say whose it is: a namesake's list never carries the same name.
    static func displayName(for child: HouseholdMember, among members: [HouseholdMember]) -> String {
        let name = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return name }
        let folded = words.map(HouseholdWorkload.normalized)
        let otherNames = members
            .filter { $0.role != .assistant && $0.id != child.id }
            .map { $0.name.split(whereSeparator: \.isWhitespace).map { HouseholdWorkload.normalized(String($0)) } }
        for length in 1 ... words.count {
            let prefix = Array(folded.prefix(length))
            if !otherNames.contains(where: { $0.starts(with: prefix) }) {
                return words.prefix(length).joined(separator: " ")
            }
        }
        return name
    }

    static func tasks(
        for child: HouseholdMember,
        in tasks: [TaskItem],
        members: [HouseholdMember],
        now: Date,
        calendar: Calendar = .current
    ) -> [TaskItem] {
        HouseholdWorkload.assignedTasks(to: child, in: tasks, members: members)
            .filter { $0.belongsOnAgenda(for: now, calendar: calendar) }
            .sorted { lhs, rhs in
                let left = sortDate(for: lhs, now: now, calendar: calendar)
                let right = sortDate(for: rhs, now: now, calendar: calendar)
                if left != right { return left < right }
                let byTitle = title(of: lhs).localizedStandardCompare(title(of: rhs))
                if byTitle != .orderedSame { return byTitle == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func rows(
        for tasks: [TaskItem],
        now: Date,
        calendar: Calendar = .current
    ) -> [ChildDayRow] {
        tasks.map { task in
            row(for: task, time: timeLabel(for: task, now: now, calendar: calendar), state: .open)
        }
    }

    static func row(for task: TaskItem, time: String?, state: ChildDayRow.State) -> ChildDayRow {
        ChildDayRow(
            id: task.id,
            title: title(of: task),
            time: time,
            symbolName: task.category.symbolName,
            state: state
        )
    }

    static func title(of task: TaskItem) -> String {
        task.title.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // A child's list carries no lateness: it shows an hour only for something that happens today.
    static func timeToday(for task: TaskItem, now: Date, calendar: Calendar = .current) -> Date? {
        guard let shown = task.displayDate(relativeTo: now, calendar: calendar) else { return nil }
        if calendar.isDate(shown, inSameDayAs: now) { return shown }
        guard task.recurrence != .none,
              let occurrence = task.scheduledOccurrence(
                  after: calendar.startOfDay(for: now).addingTimeInterval(-1),
                  calendar: calendar
              ),
              calendar.isDate(occurrence, inSameDayAs: now) else { return nil }
        return occurrence
    }

    static func timeLabel(for task: TaskItem, now: Date, calendar: Calendar = .current) -> String? {
        timeToday(for: task, now: now, calendar: calendar).map {
            formatted($0, "HH:mm", calendar: calendar)
        }
    }

    static func dateLine(for date: Date, calendar: Calendar = .current) -> String {
        formatted(date, "EEEE, d 'de' MMMM", calendar: calendar)
    }

    static func heading(name: String, dateLine: String) -> String {
        name.isEmpty ? dateLine : "\(name) · \(dateLine)"
    }

    static func shareText(name: String, dateLine: String, rows: [ChildDayRow]) -> String {
        let lines = rows.map { row in
            row.time.map { "○ \(row.title) · \($0)" } ?? "○ \(row.title)"
        }
        return ([heading(name: name, dateLine: dateLine), ""] + lines).joined(separator: "\n")
    }

    static func pages(_ rows: [ChildDayRow], perPage: Int = rowsPerPrintedPage) -> [[ChildDayRow]] {
        guard perPage > 0 else { return [] }
        return stride(from: 0, to: rows.count, by: perPage).map {
            Array(rows[$0 ..< min($0 + perPage, rows.count)])
        }
    }

    // A child's tap closes every occurrence through today, so nothing already done alerts tonight.
    static func markedDone(_ task: TaskItem, now: Date, calendar: Calendar = .current) -> TaskItem? {
        guard task.kind == .task, !task.isDone else { return nil }
        var marked = task
        guard task.recurrence != .none else {
            marked.isDone = true
            marked.completedAt = now
            return marked
        }
        guard let tomorrow = calendar.date(
                  byAdding: .day,
                  value: 1,
                  to: calendar.startOfDay(for: now)
              ),
              let next = task.scheduledOccurrence(
                  after: tomorrow.addingTimeInterval(-1),
                  calendar: calendar
              ),
              next > now else { return nil }
        marked.dueAt = next
        marked.dueLabel = AppStore.taskDueLabel(for: next, relativeTo: now, calendar: calendar)
        marked.snoozedUntil = nil
        return marked
    }

    static func reopened(_ live: TaskItem, restoring baseline: TaskItem) -> TaskItem {
        var task = live
        if baseline.recurrence == .none {
            task.isDone = baseline.isDone
            task.completedAt = baseline.completedAt
        } else {
            task.dueAt = baseline.dueAt
            task.dueLabel = baseline.dueLabel
            task.snoozedUntil = baseline.snoozedUntil
        }
        return task
    }

    private static func sortDate(for task: TaskItem, now: Date, calendar: Calendar) -> Date {
        timeToday(for: task, now: now, calendar: calendar)
            ?? task.displayDate(relativeTo: now, calendar: calendar)
            ?? .distantPast
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

struct ChildDayPresentation: Identifiable {
    let childID: HouseholdMember.ID
    let session: ChildDaySession

    var id: ChildDaySession.ID { session.id }
}

struct ChildDaySession: Identifiable {
    static let settleInterval: TimeInterval = 1

    let id = UUID()
    private(set) var day: Date
    // Fixed when the list opens: a tap never moves a row, and what arrives later joins at the end.
    private(set) var order: [TaskItem.ID]
    private(set) var marks: [TaskItem.ID: ChildDayMark] = [:]
    private var lastChangeAt: [TaskItem.ID: Date] = [:]

    init(
        child: HouseholdMember,
        tasks: [TaskItem],
        members: [HouseholdMember],
        now: Date,
        calendar: Calendar = .current
    ) {
        day = calendar.startOfDay(for: now)
        order = ChildDay.tasks(
            for: child,
            in: tasks,
            members: members,
            now: now,
            calendar: calendar
        ).map(\.id)
    }

    mutating func absorb(
        child: HouseholdMember,
        tasks: [TaskItem],
        members: [HouseholdMember],
        now: Date,
        calendar: Calendar = .current
    ) {
        let today = ChildDay.tasks(
            for: child,
            in: tasks,
            members: members,
            now: now,
            calendar: calendar
        ).map(\.id)
        guard calendar.isDate(now, inSameDayAs: day) else {
            day = calendar.startOfDay(for: now)
            order = today
            marks = [:]
            lastChangeAt = [:]
            return
        }
        var known = Set(order)
        for id in today where known.insert(id).inserted {
            order.append(id)
        }
    }

    func rows(
        child: HouseholdMember,
        tasks: [TaskItem],
        members: [HouseholdMember],
        now: Date,
        calendar: Calendar = .current
    ) -> [ChildDayRow] {
        let owned = Set(
            HouseholdWorkload.assignedTasks(to: child, in: tasks, members: members).map(\.id)
        )
        let live = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { id in
            guard let task = live[id], task.kind == .task, owned.contains(id) else { return nil }
            if let mark = marks[id], mark.holds(on: task) {
                return ChildDay.row(
                    for: task,
                    time: ChildDay.timeLabel(for: mark.baseline, now: mark.markedAt, calendar: calendar),
                    state: .doneHere
                )
            }
            if task.isDone {
                return ChildDay.row(
                    for: task,
                    time: ChildDay.timeLabel(for: task, now: now, calendar: calendar),
                    state: .doneElsewhere
                )
            }
            guard task.belongsOnAgenda(for: now, calendar: calendar) else { return nil }
            return ChildDay.row(
                for: task,
                time: ChildDay.timeLabel(for: task, now: now, calendar: calendar),
                state: .open
            )
        }
    }

    func tap(on id: TaskItem.ID, tasks: [TaskItem], now: Date) -> ChildDayTap {
        if let last = lastChangeAt[id], now.timeIntervalSince(last) < Self.settleInterval {
            return .ignore
        }
        guard let live = tasks.first(where: { $0.id == id }) else { return .ignore }
        if let mark = marks[id], mark.holds(on: live) { return .reopen(mark) }
        guard live.kind == .task, !live.isDone else { return .ignore }
        return .markDone(id)
    }

    mutating func record(_ mark: ChildDayMark) {
        marks[mark.written.id] = mark
        lastChangeAt[mark.written.id] = mark.markedAt
    }

    mutating func release(_ id: TaskItem.ID, at date: Date) {
        marks[id] = nil
        lastChangeAt[id] = date
    }
}
