import SwiftUI

enum TaskListFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case mine
    case seeds
    case shopping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tudo"
        case .mine: "Minhas"
        case .seeds: "Sementes"
        case .shopping: "Compras"
        }
    }
}

struct TasksView: View {
    @Environment(AppStore.self) private var store
    @Environment(RouterPath.self) private var router

    @State private var filter: TaskListFilter = .all
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var collapsed: Set<String> = []
    @State private var isShowingCompleted = false
    @State private var isConfirmingShoppingClear = false
    @FocusState private var isSearchFocused: Bool

    private var openTasks: [TaskItem] {
        store.tasks.filter { $0.kind == .task && !$0.isDone }
    }

    private var mine: [TaskItem] {
        guard let me = store.currentFamilyMember else { return [] }
        return openTasks.filter { $0.ownerMemberID == me.id }
    }

    private var completedToday: [TaskItem] {
        store.tasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return Calendar.current.isDateInToday(completedAt)
        }
    }

    var body: some View {
        if isSearching {
            searchScreen
        } else {
            main
        }
    }


    private var main: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    filters
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 104)
            }

            if filter != .shopping, !store.tasks.isEmpty {
                fab
            }
        }
        .ninaScreenBackground()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(filter == .shopping ? "Compras" : "Tarefas").ninaText(.screen)
                Text(subtitle).ninaText(.label, NinaTheme.muted)
            }

            Spacer()

            Button {
                Haptics.lightImpact()
                isSearching = true
                isSearchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(NinaTheme.ink)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Buscar")
            .padding(.top, 4)
        }
    }

    private var subtitle: String {
        switch filter {
        case .shopping: "A lista é da casa inteira."
        case .seeds: "O que não tem dia marcado."
        default: "Tudo o que a casa tem em aberto."
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskListFilter.allCases) { option in
                    Button {
                        Haptics.selection()
                        filter = option
                    } label: {
                        NinaChip(text: chipTitle(option), isSet: filter == option)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private func chipTitle(_ option: TaskListFilter) -> String {
        let count: Int = switch option {
        case .all: openTasks.count
        case .mine: mine.count
        case .seeds: store.openSeeds.count
        case .shopping: store.pendingShoppingItems.count
        }
        return count > 0 ? "\(option.title) \(count)" : option.title
    }

    @ViewBuilder
    private var content: some View {
        switch filter {
        case .shopping: shopping
        case .seeds: seeds
        case .mine: grouped(mine, emptyHeadline: "Nada está com você agora.", emptyBody: "Quando alguém da casa te passar alguma coisa, ela aparece aqui.")
        case .all:
            if store.tasks.isEmpty {
                firstTasks
            } else {
                grouped(openTasks, emptyHeadline: "Nada em aberto.", emptyBody: "A casa está em dia. Pode deixar assim.")
            }
        }
    }


    @ViewBuilder
    private func grouped(_ tasks: [TaskItem], emptyHeadline: String, emptyBody: String) -> some View {
        if tasks.isEmpty, completedToday.isEmpty {
            ZeroState(headline: emptyHeadline, body_: emptyBody, presence: .stored)
                .padding(.top, 40)
        } else {
            VStack(spacing: 18) {
                ForEach(categoryGroups(of: tasks), id: \.0.id) { category, items in
                    categorySection(category, items)
                }

                if !completedToday.isEmpty {
                    completedSection
                }
            }
            .padding(.top, 4)
        }
    }

    private func categoryGroups(of tasks: [TaskItem]) -> [(TaskCategory, [TaskItem])] {
        var order: [String] = []
        var buckets: [String: (TaskCategory, [TaskItem])] = [:]
        for task in tasks {
            let key = task.category.id
            if buckets[key] == nil {
                buckets[key] = (task.category, [])
                order.append(key)
            }
            buckets[key]?.1.append(task)
        }
        return order.compactMap { buckets[$0] }
    }

    private func categorySection(_ category: TaskCategory, _ items: [TaskItem]) -> some View {
        let isCollapsed = collapsed.contains(category.id)
        return VStack(spacing: 0) {
            Button {
                Haptics.selection()
                if isCollapsed { collapsed.remove(category.id) } else { collapsed.insert(category.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
                    Text("\(category.title.uppercased()) · \(items.count)")
                        .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
                    Spacer()
                    if isCollapsed {
                        Text("recolhida").ninaText(.meta, NinaTheme.faint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, isCollapsed ? 0 : 8)

            if !isCollapsed {
                ForEach(items) { task in
                    TaskRowView(task: task)
                    if task.id != items.last?.id {
                        NinaDivider(inset: 36)
                    }
                }
            }
        }
    }

    private var completedSection: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.selection()
                isShowingCompleted.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isShowingCompleted ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NinaTheme.faint)
                    Text("CONCLUÍDAS HOJE · \(completedToday.count)")
                        .ninaText(.eyebrow, NinaTheme.faint, weight: .bold)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, isShowingCompleted ? 8 : 0)

            if isShowingCompleted {
                ForEach(completedToday) { task in
                    TaskRowView(task: task)
                    if task.id != completedToday.last?.id {
                        NinaDivider(inset: 36)
                    }
                }

                Text(CompletedTaskRetention.disclosureNote)
                    .ninaText(.meta, NinaTheme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
    }

    private var firstTasks: some View {
        ZeroState(
            headline: "A casa ainda não combinou nada.",
            body_: "Tarefa aqui é coisa que a casa combinou. Pode ter dono e dia, ou pode só ficar em aberto até alguém pegar."
        ) {
            VStack(spacing: 6) {
                NinaButton(title: "Contar pra Nina", systemName: "bubble.left") {
                    Haptics.lightImpact()
                    NotificationCenter.default.post(name: .ninaSelectChatTab, object: nil)
                }
                NinaButton(title: "Escrever sem a Nina", kind: .quiet) {
                    Haptics.lightImpact()
                    router.presentedSheet = .addTask
                }
            }
        }
        .padding(.top, 44)
    }


    @ViewBuilder
    private var seeds: some View {
        if store.openSeeds.isEmpty {
            VStack(spacing: 20) {
                ZeroState(
                    headline: "Semente é vontade sem data.",
                    body_: "O que você quer fazer um dia e não quer marcar agora. Fica guardado sem cobrar nada."
                )

                // Teaching by showing the real object: a semente rendered as it
                // will look, with the date slot deliberately empty.
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Uma semente é assim")
                    HStack(spacing: 12) {
                        CategoryGlyph(systemName: "leaf", size: 18, tint: NinaTheme.ink)
                        Text("Pintar a sala")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(NinaTheme.ink)
                        Spacer()
                        Text("Plante depois").ninaText(.meta, NinaTheme.faint)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ninaCard(fill: NinaTheme.grout, stroke: .clear)

                NinaButton(title: "Plantar uma semente", kind: .outline) {
                    Haptics.lightImpact()
                    router.presentedSheet = .addTask
                }
            }
            .padding(.top, 34)
        } else {
            VStack(spacing: 0) {
                ForEach(store.openSeeds) { seed in
                    TaskRowView(task: seed)
                    if seed.id != store.openSeeds.last?.id {
                        NinaDivider(inset: 36)
                    }
                }

                Text("Semente não vira atraso e não conta no retrato da casa. Ela só vira tarefa no dia em que você tocar em Plantar.")
                    .ninaText(.caption, NinaTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .ninaCard(fill: NinaTheme.grout, stroke: .clear)
                    .padding(.top, 18)
            }
            .padding(.top, 4)
        }
    }


    @ViewBuilder
    private var shopping: some View {
        if store.shoppingItems.isEmpty {
            VStack(spacing: 22) {
                ZeroState(
                    headline: "Nada faltando por enquanto.",
                    body_: "O que acabar em casa entra aqui. Qualquer pessoa da casa pode botar na lista, e a Nina não cobra de ninguém."
                )

                addShoppingField
            }
            .padding(.top, 34)
        } else {
            VStack(spacing: 0) {
                // Checked items stay exactly where they are: in an aisle you need
                // positional stability, so nothing reflows under your thumb.
                ForEach(store.shoppingItems) { item in
                    shoppingRow(item)
                    if item.id != store.shoppingItems.last?.id {
                        NinaDivider(inset: 36)
                    }
                }

                addShoppingField.padding(.top, 16)

                if store.shoppingItems.contains(where: \.isChecked) {
                    NinaButton(title: "Limpar o que já foi comprado", kind: .quiet) {
                        Haptics.warning()
                        isConfirmingShoppingClear = true
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.top, 4)
            .alert("Limpar os comprados?", isPresented: $isConfirmingShoppingClear) {
                Button("Limpar", role: .destructive) {
                    _ = store.clearCheckedShoppingItems()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Some da lista para todo mundo da casa.")
            }
        }
    }

    private func shoppingRow(_ item: ShoppingItem) -> some View {
        HStack(spacing: 12) {
            Button {
                item.isChecked ? Haptics.selection() : Haptics.success()
                store.toggleShoppingItem(item)
            } label: {
                // Squares carry stock; circles carry things with an owner and a moment.
                NinaCheckbox(isOn: item.isChecked, isSquare: true)
            }
            .buttonStyle(.plain)

            Button {
                Haptics.lightImpact()
                router.presentedSheet = .editShoppingItem(item.id)
            } label: {
                HStack(spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(item.isChecked ? NinaTheme.muted : NinaTheme.ink)
                        .strikethrough(item.isChecked, color: NinaTheme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !item.amount.isEmpty {
                        Text(item.amount).ninaText(.meta, NinaTheme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 48)
    }

    private var addShoppingField: some View {
        Button {
            Haptics.lightImpact()
            router.presentedSheet = .addShoppingItem
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NinaTheme.cobalt)
                Text("Adicionar item")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(NinaTheme.muted)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))
        }
        .buttonStyle(.plain)
    }


    private var searchScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(NinaTheme.muted)
                    TextField("Procurar na casa", text: $searchQuery)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(NinaTheme.ink)
                        .focused($isSearchFocused)
                        .submitLabel(.search)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(NinaTheme.grout, in: RoundedRectangle(cornerRadius: NinaTheme.Radius.field, style: .continuous))

                Button("Cancelar") {
                    Haptics.selection()
                    searchQuery = ""
                    isSearching = false
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NinaTheme.cobalt)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 14)

            if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
            } else if searchResults.isEmpty {
                // No create button: someone who searched does not want to invent
                // the thing, they want to find it.
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nada com esse nome.").ninaText(.screen)
                    Text("Procurei em tarefas, sementes e compras, abertas e concluídas. Pode estar guardado com outra palavra.")
                        .ninaText(.label, NinaTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            Haptics.selection()
                            searchQuery = ""
                            isSearching = false
                            filter = .all
                        } label: {
                            NinaChip(text: "Ver tudo em aberto")
                        }
                        .buttonStyle(.plain)

                        Button {
                            Haptics.lightImpact()
                            searchQuery = ""
                            isSearching = false
                            NotificationCenter.default.post(name: .ninaSelectChatTab, object: nil)
                        } label: {
                            NinaChip(text: "Perguntar pra Nina", isSet: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { task in
                            TaskRowView(task: task)
                            NinaDivider(inset: 36)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ninaScreenBackground()
    }

    private var searchResults: [TaskItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return store.tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(query)
                || task.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var fab: some View {
        Button {
            Haptics.lightImpact()
            router.presentedSheet = .addTask
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(NinaTheme.onCobalt)
                .frame(width: 56, height: 56)
                .background(NinaTheme.cobalt, in: Circle())
                .cardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Adicionar")
        .padding(.trailing, 20)
        .padding(.bottom, 96)
    }
}
