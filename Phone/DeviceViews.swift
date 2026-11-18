import SwiftUI
import UIKit

/// A device's card: who can reach it, how it glows, what it does, its name;
/// a board's new token; disconnecting. Each row opens a page of its own.
/// «Как светится» waits for firmware that describes its own settings.
struct DeviceCard: View {
    @EnvironmentObject var model: AppModel
    let id: String

    @State private var confirmingToken = false
    @State private var token: String?
    @State private var removing = false

    static func who(_ id: String) -> String { "who:" + id }
    static func does(_ id: String) -> String { "does:" + id }
    static func name(_ id: String) -> String { "name:" + id }

    /// A path element in «Игрушки»: which page, for which device.
    static func page(_ element: String) -> (String, String) {
        guard let colon = element.firstIndex(of: ":") else { return ("card", element) }
        return (String(element[..<colon]), String(element[element.index(after: colon)...]))
    }

    private var device: Device? { model.devices.first { $0.id == id } }

    var body: some View {
        Group {
            if let device {
                card(device)
            } else {
                Text(tr("Этого устройства уже нет"))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.paper)
        // The name is the back button's on the card's pages («‹ Котик на
        // полке»); the card itself shows it big, so not in the bar too.
        .navigationTitle(device?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text(verbatim: "") }
        }
    }

    private func card(_ device: Device) -> some View {
        List {
            Section {
                header(device)
            }
            .listRowBackground(Color.clear)
            Section {
                NavigationLink(value: Self.who(id)) {
                    row("heart.fill", tint: Theme.link, title: tr("Кто может достучаться"), sub: Self.reachLine(device))
                }
                .accessibilityIdentifier("deviceWho")
                row("sun.max.fill", tint: Theme.faint, title: tr("Как светится"),
                    sub: tr("Пока нечего настраивать: настройки пришлёт новая прошивка"), muted: true)
                NavigationLink(value: Self.does(id)) {
                    row("arrow.left.arrow.right", tint: Theme.ok, title: tr("Что делает"), sub: Self.doesLine(device))
                }
                .accessibilityIdentifier("deviceDoes")
                NavigationLink(value: Self.name(id)) {
                    row("pencil", tint: Theme.muted, title: tr("Название"), sub: device.name)
                }
                .accessibilityIdentifier("deviceName")
            }
            .listRowBackground(Theme.field)
            if !device.paired {
                tokenSection
            }
            Section {
                Button(tr("Отключить"), role: .destructive) { removing = true }
                    .accessibilityIdentifier("removeDevice")
            } footer: {
                Text(device.paired ? tr("Вернуть его можно по коду с экрана устройства.") : "")
            }
            .listRowBackground(Theme.field)
        }
        .scrollContentBackground(.hidden)
        .alert(tr("Выпустить новый токен?"), isPresented: $confirmingToken) {
            Button(tr("Выпустить"), role: .destructive) { issueToken(device) }
            Button(tr("Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Старый перестанет работать сразу, и «{name}» отключится, пока ты не вставишь новый в прошивку.", ["name": device.name]))
        }
        .alert(tr("Отключить {name}?", ["name": device.name]), isPresented: $removing) {
            Button(tr("Отключить"), role: .destructive) {
                Task { await model.removeDevice(device) }
            }
            Button(tr("Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Оно перестанет получать и отправлять сердечки. Подключить снова можно в любой момент."))
        }
        .sheet(isPresented: Binding(get: { token != nil }, set: { if !$0 { token = nil } })) {
            NavigationStack {
                NewTokenView(name: device.name, token: token ?? "")
            }
            .interactiveDismissDisabled()
        }
    }

    private var tokenSection: some View {
        Section {
            Button {
                confirmingToken = true
            } label: {
                Label(tr("Выпустить новый токен"), systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("newToken")
        } footer: {
            Text(tr("Токен показывают один раз. Потерялся — выпусти новый: старый перестанет работать сразу, и новый надо будет вставить в прошивку."))
        }
        .listRowBackground(Theme.field)
    }

    private func header(_ device: Device) -> some View {
        VStack(spacing: 8) {
            Image(systemName: DeviceRow.symbol(device.kind))
                .font(.system(size: 32))
                .foregroundStyle(Theme.heart)
                .frame(width: 76, height: 76)
                .background(Theme.heartSoft, in: Circle())
            Text(device.name)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(Self.kindName(device.kind) + DeviceRow.seen(device))
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func row(_ symbol: String, tint: Color, title: String, sub: String, muted: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(muted ? Theme.muted : Theme.ink)
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func issueToken(_ device: Device) {
        Task {
            do {
                token = try await model.newDeviceToken(device)
            } catch {
                model.show(tr("Не получилось, попробуй ещё раз"), failed: true)
            }
        }
    }

    static func kindName(_ kind: String?) -> String {
        switch kind {
        case "watch": return tr("Часы")
        case "lamp": return tr("Лампа")
        case "custom": return tr("Своя плата")
        case "toy": return tr("Игрушка")
        default: return tr("Устройство")
        }
    }

    /// «Книга и кто-нибудь на свете · тихо 23:00–08:00».
    static func reachLine(_ device: Device) -> String {
        guard device.receives else { return tr("Не принимает сердечки") }
        let who = device.accept_anyone == true ? tr("Книга и кто-нибудь на свете") : tr("Только книга")
        guard let quiet = device.quiet_hours else { return who + " · " + tr("круглые сутки") }
        return who + " · " + tr("тихо {from}–{to}", ["from": quiet.from, "to": quiet.to])
    }

    static func doesLine(_ device: Device) -> String {
        switch (device.receives, device.sends) {
        case (true, true): return tr("Принимает и отправляет")
        case (true, false): return tr("Принимает")
        case (false, true): return tr("Отправляет")
        case (false, false): return tr("Ничего не делает")
        }
    }
}

/// «Кто может достучаться»: hearts from anyone in the world, and quiet hours.
/// The server keeps both, so they work with any firmware. Nothing is held:
/// a heart in the quiet hours never reaches the device.
struct DeviceWhoView: View {
    @EnvironmentObject var model: AppModel
    let id: String

    @State private var from = DeviceWhoView.date("23:00")
    @State private var to = DeviceWhoView.date("08:00")
    @State private var saving: Task<Void, Never>?

    private var device: Device? { model.devices.first { $0.id == id } }

    var body: some View {
        Form {
            if let device {
                Section {
                    Toggle(isOn: anyone(device)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("Кому-нибудь на свете"))
                            Text(tr("Сердечко от случайного человека"))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("acceptAnyone")
                } footer: {
                    Text(tr("Сердечки от людей из книги приходят всегда, кроме тихих часов."))
                }
                .listRowBackground(Theme.field)
                Section {
                    Toggle(tr("Тихие часы"), isOn: quiet(device))
                        .accessibilityIdentifier("quietHours")
                    if device.quiet_hours != nil {
                        DatePicker(tr("с"), selection: $from, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("quietFrom")
                        DatePicker(tr("до"), selection: $to, displayedComponents: .hourAndMinute)
                            .accessibilityIdentifier("quietTo")
                    }
                } footer: {
                    Text(note(device))
                }
                .listRowBackground(Theme.field)
            }
        }
        .tint(Theme.link)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Кто может достучаться"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: from) { save() }
        .onChange(of: to) { save() }
    }

    private func anyone(_ device: Device) -> Binding<Bool> {
        Binding(get: { device.accept_anyone ?? false }, set: { on in
            Task { await model.changeDevice(id, DeviceChange(acceptAnyone: on)) }
        })
    }

    private func quiet(_ device: Device) -> Binding<Bool> {
        Binding(get: { device.quiet_hours != nil }, set: { on in
            let hours = QuietHours(from: Self.hhmm(from), to: Self.hhmm(to), tz: TimeZone.current.identifier)
            Task { await model.changeDevice(id, DeviceChange(quietHours: .some(on ? hours : nil))) }
        })
    }

    private func load() {
        guard let quiet = device?.quiet_hours else { return }
        from = Self.date(quiet.from)
        to = Self.date(quiet.to)
    }

    /// After the wheel stops: a change of times only, never on opening.
    private func save() {
        guard let stored = device?.quiet_hours else { return }
        let hours = QuietHours(from: Self.hhmm(from), to: Self.hhmm(to), tz: TimeZone.current.identifier)
        guard (hours.from, hours.to) != (stored.from, stored.to), hours.from != hours.to else { return }
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await model.changeDevice(id, DeviceChange(quietHours: .some(hours)))
        }
    }

    private func note(_ device: Device) -> String {
        let base = tr("В эти часы сердечки на устройство не приходят и потом не придут. На телефон и другие устройства — как обычно.")
        if let tz = device.quiet_hours?.tz, tz != TimeZone.current.identifier {
            return base + " " + tr("Время — по часовому поясу {tz}.", ["tz": tz])
        }
        return base + " " + tr("Время — как на этом телефоне.")
    }

    static func date(_ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        let hour = parts.first ?? 0, minute = parts.count > 1 ? parts[1] : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    static func hhmm(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// «Что делает»: receives, sends. A paired device can switch off what it
/// asked for and back on; a board anything. Both off is fine: it stays in
/// the account and does nothing.
struct DeviceDoesView: View {
    @EnvironmentObject var model: AppModel
    let id: String

    private var device: Device? { model.devices.first { $0.id == id } }

    var body: some View {
        Form {
            if let device {
                Section {
                    toggle(device, "receive", title: tr("Принимает сердечки"),
                           sub: device.may("receive") ? nil : tr("Не просило при подключении"))
                        .accessibilityIdentifier("doesReceive")
                    toggle(device, "send", title: tr("Отправляет сердечки"), sub: sendNote(device))
                        .accessibilityIdentifier("doesSend")
                } footer: {
                    Text(device.paired
                         ? tr("Можно выключить то, что устройство просило при подключении, и включить обратно. Выключишь всё — оно останется в аккаунте, но ничего не будет делать.")
                         : tr("Своей плате можно включить что угодно. Выключишь всё — она останется в аккаунте, но ничего не будет делать."))
                }
                .listRowBackground(Theme.field)
            }
        }
        .tint(Theme.link)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Что делает"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendNote(_ device: Device) -> String {
        if !device.may("send") { return tr("Не просило при подключении") }
        return device.sends ? tr("Для этого видит твоих людей") : tr("Включишь — увидит твоих людей")
    }

    private func toggle(_ device: Device, _ capability: String, title: String, sub: String?) -> some View {
        Toggle(isOn: Binding(get: { device.capabilities.contains(capability) }, set: { on in
            var capabilities = Set(device.capabilities)
            if on { capabilities.insert(capability) } else { capabilities.remove(capability) }
            Task { await model.changeDevice(id, DeviceChange(capabilities: capabilities.sorted())) }
        })) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let sub {
                    Text(sub)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .disabled(!device.may(capability))
    }
}

/// «Название»: what the device is called in every app; only its owner sees it.
struct DeviceNameView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let id: String

    @State private var name = ""
    @State private var busy = false

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField(tr("Например, Котик на полке"), text: $name)
                    .accessibilityIdentifier("deviceNameField")
                    .submitLabel(.done)
                    .onSubmit(save)
            } footer: {
                Text(tr("Так устройство называется во всех твоих приложениях. Видишь название только ты."))
            }
            .listRowBackground(Theme.field)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Название"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Готово"), action: save)
                    .disabled(trimmed.isEmpty || busy)
                    .accessibilityIdentifier("saveName")
            }
        }
        .onAppear { name = model.devices.first { $0.id == id }?.name ?? "" }
    }

    private func save() {
        let new = String(trimmed.prefix(64))
        guard !new.isEmpty else { return }
        guard new != model.devices.first(where: { $0.id == id })?.name else {
            dismiss()
            return
        }
        busy = true
        Task {
            if await model.changeDevice(id, DeviceChange(name: new)) {
                dismiss()
            }
            busy = false
        }
    }
}

/// A board's new token, shown once, to paste into its firmware.
struct NewTokenView: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let token: String

    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Text(token)
                    .font(.system(size: 15, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("newTokenValue")
                Button {
                    UIPasteboard.general.string = token
                    copied = true
                } label: {
                    Label(copied ? tr("Скопировано") : tr("Скопировать токен"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text(tr("Новый токен для «{name}»", ["name": name]))
            } footer: {
                Text(tr("Старый уже не работает. Мы покажем новый только сейчас: скопируй и вставь в прошивку вместо старого. С ним можно отправлять сердечки от твоего имени, так что никому не показывай."))
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
        .navigationTitle(tr("Новый токен"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Готово")) { dismiss() }
                    .accessibilityIdentifier("tokenDone")
            }
        }
    }
}
