import SwiftUI
import UIKit

/// The person's own devices: a watch, a lamp, a board. Toys over Bluetooth
/// come later (one shared protocol, a catalog on the server); for now a
/// device joins by the six digits on its screen, or a board by its token.
struct ToysView: View {
    @EnvironmentObject var model: AppModel
    @State private var addingBoard = false
    @State private var removing: Device?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(tr("Игрушка, лампа или своя плата, которая светится, когда о тебе думают, или отправляет сердечко по кнопке."))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.muted)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }
                Section(tr("Устройства")) {
                    if let problem = model.devicesProblem {
                        Text(problem).foregroundStyle(Theme.danger)
                    } else if !model.devicesLoaded {
                        ProgressView()
                    } else if model.devices.isEmpty {
                        Text(tr("Пока ни одного."))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(model.devices) { device in
                        DeviceRow(device: device)
                            .swipeActions {
                                Button(tr("Отключить"), role: .destructive) { removing = device }
                            }
                    }
                }
                .listRowBackground(Theme.field)
                Section {
                    Button { model.pairing = AppModel.Pairing(code: "") } label: {
                        Label(tr("Подключить по коду"), systemImage: "number")
                    }
                    .accessibilityIdentifier("pairByCode")
                    Button { addingBoard = true } label: {
                        Label(tr("Своя плата"), systemImage: "cpu")
                    }
                    .accessibilityIdentifier("addBoard")
                    HStack {
                        Label(tr("Игрушки по Bluetooth"), systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(Theme.faint)
                        Spacer()
                        Text(tr("скоро"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.well, in: Capsule())
                    }
                } footer: {
                    Text(tr("Код на шесть цифр показывают часы и лампы. Своей плате нужен токен: его вставляют в прошивку."))
                }
                .listRowBackground(Theme.field)
                Section {
                    Link(destination: URL(string: Config.site + "/docs")!) {
                        Label(tr("Как подключить свою плату"), systemImage: "book")
                    }
                }
                .listRowBackground(Theme.field)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(tr("Игрушки"))
            .refreshable { await model.loadDevices() }
            .task { await model.loadDevices() }
            .sheet(isPresented: $addingBoard) {
                NavigationStack { BoardView() }
            }
            .alert(tr("Отключить {name}?", ["name": removing?.name ?? ""]),
                   isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button(tr("Отключить"), role: .destructive) {
                    if let device = removing {
                        Task { await model.removeDevice(device) }
                    }
                    removing = nil
                }
                Button(tr("Отмена"), role: .cancel) { removing = nil }
            } message: {
                Text(tr("Оно перестанет получать и отправлять сердечки. Подключить снова можно в любой момент."))
            }
        }
    }
}

struct DeviceRow: View {
    let device: Device

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: DeviceRow.symbol(device.kind))
                .font(.system(size: 18))
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Theme.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ kind: String?) -> String {
        switch kind {
        case "watch": return "applewatch"
        case "lamp": return "lamp.table"
        case "custom": return "cpu"
        default: return "lightbulb"
        }
    }

    private var detail: String {
        let can = device.receives && device.sends ? tr("Принимает и отправляет")
            : device.receives ? tr("Принимает") : tr("Отправляет")
        guard let seen = device.last_seen_at.flatMap(Self.parse) else {
            return can + tr(" · ещё не подключался")
        }
        let ago = RelativeDateTimeFormatter().localizedString(for: seen, relativeTo: Date())
        return can + tr(" · был онлайн {ago}", ["ago": ago])
    }

    private static func parse(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return full.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// «Подключить по коду»: the six digits a watch or a lamp shows. The device
/// gets its token from the server; this phone never sees it.
struct PairView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var code: String
    @State private var card: PairingCard?
    @State private var looking = false
    @State private var busy = false
    @State private var problem: String?
    @State private var done: String?
    @FocusState private var focused: Bool

    init(code: String = "") {
        _code = State(initialValue: code)
    }

    var body: some View {
        Form {
            if let done {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.ok)
                        Text(tr("Подключено"))
                            .font(.system(size: 22, weight: .bold))
                        Text(tr("{name} теперь в твоём аккаунте.", ["name": done]))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section {
                    TextField("000 000", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .accessibilityLabel(tr("Код с экрана устройства"))
                        .accessibilityIdentifier("pairCode")
                        .onChange(of: code) { _, typed in
                            let digits = String(typed.filter(\.isNumber).prefix(6))
                            if digits != typed { code = digits }
                            card = nil
                            problem = nil
                            look()
                        }
                } header: {
                    Text(tr("Код с экрана устройства"))
                } footer: {
                    if let problem {
                        Text(problem).foregroundStyle(Theme.danger)
                    } else if looking {
                        Text(tr("Ищем устройство…"))
                    } else if card == nil {
                        Text(tr("Цифры видны на экране часов, лампы или другого устройства. Код живёт 10 минут."))
                    }
                }
                if let card {
                    Section {
                        Label(card.name, systemImage: DeviceRow.symbol(card.kind))
                            .font(.system(size: 17, weight: .semibold))
                        ForEach(promises(card.capabilities), id: \.self) { line in
                            Text("· " + line).foregroundStyle(Theme.muted)
                        }
                    }
                    Section(tr("В аккаунт")) {
                        Text(model.email ?? "")
                    }
                    Section {
                        Button(action: confirm) {
                            Text(busy ? tr("Подключаем…") : tr("Подключить"))
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(busy)
                        .accessibilityIdentifier("confirmPairing")
                    } footer: {
                        Text(tr("Подключай только свои устройства. Если код тебе прислали, не вводи его."))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Подключить устройство"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if done != nil {
                    Button(tr("Готово")) { dismiss() }
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                if done == nil {
                    Button(tr("Отмена")) { dismiss() }
                }
            }
        }
        .onAppear {
            if code.isEmpty { focused = true } else { look() }
        }
    }

    /// What the card promises, from what the device asked for. The server
    /// holds the device to it: without `send` it can't read the people either.
    private func promises(_ caps: [String]) -> [String] {
        let receives = caps.contains("receive"), sends = caps.contains("send")
        if receives && sends { return [tr("увидит твоих людей"), tr("будет отправлять и получать сигналы")] }
        if sends { return [tr("увидит твоих людей"), tr("будет отправлять сигналы, получать не будет")] }
        return [tr("будет получать сигналы"), tr("людей не увидит, отправлять не сможет")]
    }

    private func message(_ error: Error) -> String {
        let status = (error as? APIError)?.status
        if status == 404 { return tr("Такого кода нет или он устарел. Проверь цифры или попроси у устройства новый.") }
        if status == 429 { return tr("Слишком много попыток, попробуй через час") }
        return (error as? LocalizedError)?.errorDescription ?? tr("Не получилось, попробуй ещё раз")
    }

    private func look() {
        guard code.count == 6, !looking else { return }
        let wanted = code
        looking = true
        Task {
            defer { looking = false }
            do {
                let found = try await model.findPairing(wanted)
                if code == wanted { card = found }
            } catch {
                if code == wanted { problem = message(error) }
            }
        }
    }

    private func confirm() {
        guard let card else { return }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                try await model.confirmPairing(code)
                done = card.name
            } catch {
                problem = message(error)
                if (error as? APIError)?.status == 404 { self.card = nil }
            }
        }
    }
}

/// A board of one's own: a name and what it does, then its token, shown once.
struct BoardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var receives = true
    @State private var sends = true
    @State private var busy = false
    @State private var problem: String?
    @State private var token: String?
    @State private var copied = false

    init(shownToken: String? = nil) {
        _token = State(initialValue: shownToken)
        if shownToken != nil { _name = State(initialValue: "Котик на полке") }
    }

    var body: some View {
        Form {
            if let token {
                Section {
                    Text(token)
                        .font(.system(size: 15, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("boardToken")
                    Button {
                        UIPasteboard.general.string = token
                        copied = true
                    } label: {
                        Label(copied ? tr("Скопировано") : tr("Скопировать токен"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                } header: {
                    Text(tr("«{name}» подключено", ["name": name]))
                } footer: {
                    Text(tr("Это токен устройства. Мы покажем его только сейчас: скопируй и вставь в прошивку. С ним можно отправлять сердечки от твоего имени, так что никому не показывай."))
                }
                Section {
                    Link(destination: URL(string: Config.site + "/docs")!) {
                        Label(tr("Как подключить свою плату"), systemImage: "book")
                    }
                }
            } else {
                Section(tr("Название")) {
                    TextField(tr("Например, Котик на полке"), text: $name)
                        .accessibilityIdentifier("boardName")
                }
                Section {
                    Toggle(tr("Принимает сердечки"), isOn: $receives)
                    Toggle(tr("Отправляет сердечки"), isOn: $sends)
                }
                if let problem {
                    Section { Text(problem).foregroundStyle(Theme.danger) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Своя плата"))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(token != nil && !copied)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if token == nil {
                    Button(tr("Отмена")) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if token == nil {
                    Button(tr("Подключить"), action: create)
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || (!receives && !sends))
                        .accessibilityIdentifier("createBoard")
                } else {
                    Button(tr("Готово")) { dismiss() }
                }
            }
        }
    }

    private func create() {
        busy = true
        problem = nil
        let caps = (receives ? ["receive"] : []) + (sends ? ["send"] : [])
        Task {
            defer { busy = false }
            do {
                token = try await model.addBoard(name: name.trimmingCharacters(in: .whitespaces), capabilities: caps)
            } catch APIError.status(409, "too many devices") {
                problem = tr("Устройств уже много, отключи лишние")
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? tr("Не получилось, попробуй ещё раз")
            }
        }
    }
}
