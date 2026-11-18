import SwiftUI

/// The whole book: «Рядом» in the order set by hand (drag to change it), the
/// others the most recently signalled first. A tap sends a heart; the
/// pencil opens the person's card.
struct BookView: View {
    @EnvironmentObject var model: AppModel
    @State private var editing: Contact?
    @State private var search = ""

    var body: some View {
        NavigationStack {
            list
                .scrollContentBackground(.hidden)
                .background(Theme.paper)
                .navigationTitle(tr("Книга"))
                .searchable(text: $search, prompt: tr("Найти"))
                .toolbar { bookToolbar }
                .refreshable { await model.reload() }
                .sheet(item: $editing) { contact in
                    NavigationStack { ContactEditor(contact: contact) }
                }
        }
    }

    private var list: some View {
        List {
            if model.contacts.isEmpty && model.loaded {
                EmptyBook()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if !close.isEmpty {
                closeSection
            }
            if !others.isEmpty {
                Section(tr("Остальные")) {
                    ForEach(others) { contact in row(contact) }
                }
            }
            if model.inviteURL != nil {
                shareSection
            }
        }
    }

    private var closeSection: some View {
        Section {
            ForEach(close) { contact in row(contact) }
                .onMove(perform: reorder)
        } header: {
            Text(tr("Рядом"))
        } footer: {
            if search.isEmpty {
                Text(tr("Кружки на главном экране, в этом порядке."))
            }
        }
    }

    private var shareSection: some View {
        Section {
            ShareLink(item: model.shareText) {
                Label(tr("Поделиться своим Love ID"), systemImage: "square.and.arrow.up")
            }
        } footer: {
            Text(tr("Отправь его тем, кто хочет нажимать, когда думает о тебе."))
        }
    }

    /// No `if` around a ToolbarItem: Xcode 16 then finds `toolbar` ambiguous.
    @ToolbarContentBuilder
    private var bookToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.closeContacts.count > 1 && search.isEmpty {
                EditButton()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { model.adding = AppModel.Adding(invite: "") } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(tr("Добавить по ссылке"))
            .accessibilityIdentifier("bookAdd")
        }
    }

    /// Dragging works on the whole «Рядом» only, not on search results.
    private var reorder: ((IndexSet, Int) -> Void)? {
        guard search.isEmpty else { return nil }
        let model = model
        return { source, destination in model.moveClose(from: source, to: destination) }
    }

    private var close: [Contact] { model.closeContacts.filter(matches) }
    private var others: [Contact] { model.otherContacts.filter(matches) }

    private func matches(_ contact: Contact) -> Bool {
        search.isEmpty || contact.label.localizedStandardContains(search)
    }

    private func row(_ contact: Contact) -> some View {
        HStack(spacing: 14) {
            Button { model.send(contact) } label: {
                HStack(spacing: 14) {
                    PersonCircle(contact: contact, sent: model.justSent == contact.id, size: 40, named: false)
                    Text(contact.label)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "heart")
                        .foregroundStyle(Theme.heart)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(contact.label)
            .accessibilityHint(tr("Отправить сердечко"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("send-\(contact.label)")
            Button { editing = contact } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(Theme.muted)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(tr("Изменить"))
            .accessibilityIdentifier("edit-\(contact.label)")
        }
        .listRowBackground(Theme.field)
        .swipeActions {
            Button(contact.isClose ? tr("Убрать из «Рядом»") : tr("В «Рядом»")) {
                model.setClose(contact, !contact.isClose)
            }
            .tint(Theme.link)
        }
    }
}

/// The twelve colors in two rows of six.
struct ColorSwatches: View {
    @Binding var selection: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(Palette.all.indices, id: \.self) { index in
                Button { selection = index } label: {
                    Circle()
                        .fill(Palette.color(index))
                        .frame(width: 38, height: 38)
                        .overlay {
                            if selection == index {
                                Circle().strokeBorder(Theme.paper, lineWidth: 3).padding(3)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Palette.all[index].name)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// A person's card: the name, the color, «Рядом», their Love ID, removing.
struct ContactEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let contact: Contact

    @State private var label: String
    @State private var color: Int
    @State private var close: Bool
    @State private var busy = false
    @State private var problem: String?
    @State private var confirmRemove = false

    init(contact: Contact) {
        self.contact = contact
        _label = State(initialValue: contact.label)
        _color = State(initialValue: contact.color ?? 0)
        _close = State(initialValue: contact.isClose)
    }

    var body: some View {
        Form {
            Section(tr("Имя")) {
                TextField(tr("Например, Мама"), text: $label)
                    .accessibilityIdentifier("contactName")
            }
            Section(tr("Цвет")) {
                ColorSwatches(selection: $color)
            }
            Section {
                Toggle(tr("Рядом"), isOn: $close)
                    .disabled(!contact.isClose && model.closeFull)
            } footer: {
                Text(!contact.isClose && model.closeFull
                     ? tr("Рядом уже 12 человек: сначала убери кого-нибудь.")
                     : tr("Кружок на главном экране."))
            }
            if let link = contact.invite_url {
                Section {
                    ShareLink(item: link) {
                        Label(tr("Love ID: {name}", ["name": contact.label]), systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text(link)
                }
            }
            if let problem {
                Section { Text(problem).foregroundStyle(Theme.danger) }
            }
            Section {
                Button(tr("Удалить из книги"), role: .destructive) { confirmRemove = true }
                    .accessibilityIdentifier("removeContact")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(contact.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(tr("Отмена")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Готово"), action: save)
                    .disabled(busy || label.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("saveContact")
            }
        }
        .alert(tr("Удалить из книги?"), isPresented: $confirmRemove) {
            Button(tr("Удалить"), role: .destructive, action: remove)
            Button(tr("Отмена"), role: .cancel) {}
        } message: {
            Text(tr("{name} не узнает об этом.", ["name": contact.label]))
        }
    }

    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await model.updateContact(contact, label: label.trimmingCharacters(in: .whitespaces), color: color, close: close)
                dismiss()
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? tr("Не получилось сохранить")
            }
        }
    }

    private func remove() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await model.remove(contact)
                dismiss()
            } catch {
                problem = tr("Не получилось удалить")
            }
        }
    }
}

/// «Добавить по ссылке»: the person's Love ID link, a name, a color.
struct AddContactView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var link: String
    @State private var label = ""
    @State private var color: Int?
    @State private var close: Bool?
    @State private var busy = false
    @State private var problem: String?

    init(invite: String) {
        _link = State(initialValue: invite)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField(tr("Вставь ссылку, которую тебе прислали"), text: $link, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                        .accessibilityIdentifier("inviteLink")
                    PasteButton(payloadType: String.self) { strings in
                        if let text = strings.first { link = text }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
            } header: {
                Text(tr("Ссылка-приглашение"))
            } footer: {
                if !link.isEmpty && code == nil {
                    Text(tr("Не похоже на ссылку-приглашение")).foregroundStyle(Theme.danger)
                } else if let code, model.isOwn(code) {
                    Text(tr("Это твоя собственная ссылка")).foregroundStyle(Theme.danger)
                }
            }
            Section(tr("Как назовёшь?")) {
                TextField(tr("Например, Мама"), text: $label)
                    .accessibilityIdentifier("newName")
            }
            Section(tr("Цвет")) {
                ColorSwatches(selection: Binding(get: { color ?? model.freeColor }, set: { color = $0 }))
            }
            Section {
                Toggle(tr("Рядом"), isOn: Binding(get: { close ?? !model.closeFull }, set: { close = $0 }))
                    .disabled(model.closeFull)
            } footer: {
                Text(model.closeFull ? tr("Рядом уже 12 человек: сначала убери кого-нибудь.") : tr("Кружок на главном экране."))
            }
            if let problem {
                Section { Text(problem).foregroundStyle(Theme.danger) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Добавить по ссылке"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(tr("Отмена")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Добавить"), action: add)
                    .disabled(!ready || busy)
                    .accessibilityIdentifier("addContact")
            }
        }
        .onAppear {
            // Picked once, so the swatches don't jump while typing.
            if color == nil { color = model.freeColor }
        }
    }

    private var code: String? { AppModel.inviteID(from: link) }

    private var ready: Bool {
        guard let code, !model.isOwn(code) else { return false }
        return !label.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        guard let code else { return }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                try await model.addContact(code: code, label: label.trimmingCharacters(in: .whitespaces),
                                           color: color ?? model.freeColor, close: close ?? !model.closeFull)
                dismiss()
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? tr("Не получилось сохранить")
            }
        }
    }
}
