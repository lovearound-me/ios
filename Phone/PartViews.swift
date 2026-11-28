import SwiftUI

/// A part's page, drawn from the catalog: only the settings the device
/// listed for it. A change shows at once and goes to the server a moment
/// later; the line on top says whether the device has it yet.
struct PartView: View {
    @EnvironmentObject var model: AppModel
    let id: String
    let partID: String

    private var device: Device? { model.devices.first { $0.id == id } }
    private var part: DevicePart? { device?.about?.shownParts.first { $0.id == partID } }

    var body: some View {
        Group {
            if let device, let part, let kind = part.known {
                List {
                    Section {
                        AppliedLine(device: device, light: kind == .light)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    }
                    page(kind, device, part)
                }
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    if kind != .button {
                        Button {
                            Task { await model.preview(device) }
                        } label: {
                            Label(tr("Проверить"), systemImage: "heart.fill")
                        }
                        .buttonStyle(WideButton(filled: true))
                        .shadow(color: Theme.link.opacity(0.28), radius: 9, y: 6)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .accessibilityIdentifier("partPreview")
                    }
                }
            } else {
                Text(tr("Этого устройства уже нет"))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(Theme.link)
        .background(Theme.paper)
        .navigationTitle(part.flatMap { device?.about?.title($0) } ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func page(_ kind: PartKind, _ device: Device, _ part: DevicePart) -> some View {
        let its = PartSetter(model: model, device: device, part: part)
        switch kind {
        case .light: LightPage(its: its)
        case .sound: SoundPage(its: its)
        case .vibration: VibrationPage(its: its)
        case .motion: MotionPage(its: its)
        case .switch: SwitchPage(its: its)
        case .screen: ScreenPage(its: its)
        case .button: ButtonPage(its: its)
        }
    }
}

/// Reads and writes one part's settings.
@MainActor
struct PartSetter {
    let model: AppModel
    let device: Device
    let part: DevicePart

    func has(_ setting: String) -> Bool { part.has(setting) }
    func value(_ setting: String) -> JSONValue { device.value(part, setting) }
    func put(_ setting: String, _ value: JSONValue) { model.setValue(device.id, part, setting, value) }

    func bool(_ setting: String) -> Binding<Bool> {
        Binding(get: { value(setting).bool ?? false }, set: { put(setting, .bool($0)) })
    }

    func level(_ setting: String) -> Binding<Double> {
        Binding(get: { Double(value(setting).int ?? 0) }, set: { new in
            let whole = Int(new.rounded())
            if whole != value(setting).int { put(setting, .int(whole)) }
        })
    }

    func int(_ setting: String) -> Binding<Int> {
        Binding(get: { value(setting).int ?? 0 }, set: { put(setting, .int($0)) })
    }

    func text(_ setting: String) -> String { value(setting).string ?? "" }
}

/// «Уже светится так», or that the change waits for the device.
struct AppliedLine: View {
    @EnvironmentObject var model: AppModel
    let device: Device
    var light = false

    private var reachable: Bool {
        device.throughPhone ? model.toys.near.contains(device.id) : device.online == true
    }

    var body: some View {
        if device.isApplied {
            Label(light ? tr("«{name}» уже светится так", ["name": device.name]) : tr("Устройство уже так настроено"),
                  systemImage: "checkmark")
                .font(.app(14))
                .foregroundStyle(Theme.ok)
                .accessibilityIdentifier("appliedLine")
        } else {
            Label(reachable ? tr("Передаём устройству…")
                  : tr("Сейчас не на связи. Применится, когда устройство выйдет на связь."),
                  systemImage: "clock")
                .font(.app(14))
                .foregroundStyle(Theme.star)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.star.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("pendingLine")
        }
    }
}

/// «Свет»: on, a color of the twelve or a different one each time, the
/// device's own effects, brightness, speed, how long, a night light.
private struct LightPage: View {
    let its: PartSetter
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        Section {
            Toggle(tr("Светиться на сердечко"), isOn: its.bool("on"))
                .accessibilityIdentifier("partOn")
        }
        .listRowBackground(Theme.field)
        if its.has("color") {
            Section(tr("Цвет")) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Palette.all.indices, id: \.self) { i in
                        let hex = Catalog.hex(i)
                        Button { its.put("color", .string(hex)) } label: {
                            swatch(Color(hex: Palette.all[i].color), picked: its.text("color").uppercased() == hex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Palette.all[i].name)
                        .accessibilityIdentifier("color-\(i)")
                        .accessibilityAddTraits(its.text("color").uppercased() == hex ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
                Button { its.put("color", .string("random")) } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(AngularGradient(colors: [0xF07A62, 0xE5A93B, 0x6FAE7C, 0x3FB3A8, 0x4E9BD8, 0x9B83DD, 0xE86A9A, 0xF07A62].map { Color(hex: $0) },
                                                  center: .center))
                            .frame(width: 22, height: 22)
                        Text(tr("Каждый раз другой")).foregroundStyle(Theme.ink)
                        Spacer()
                        if its.text("color") == "random" {
                            Image(systemName: "checkmark").font(.app(15, weight: .bold)).foregroundStyle(Theme.link)
                        }
                    }
                }
                .accessibilityIdentifier("colorRandom")
            }
            .listRowBackground(Theme.field)
        }
        Section(tr("Как")) {
            if its.has("effect"), let effects = its.part.effects, !effects.isEmpty {
                Chips(options: effects, picked: its.text("effect"), name: Catalog.effect) { its.put("effect", .string($0)) }
            }
            if its.has("brightness") { LevelRow(title: tr("Яркость"), value: its.level("brightness"), range: 1...100, percent: true) }
            if its.has("speed") { LevelRow(title: tr("Скорость"), value: its.level("speed"), range: 1...100) }
            if its.has("duration") {
                StepRow(title: tr("Сколько светится"), value: its.int("duration"), range: 1...60, text: Catalog.seconds_)
            }
            if its.has("auto_brightness") { Toggle(tr("Яркость по освещению"), isOn: its.bool("auto_brightness")) }
        }
        .listRowBackground(Theme.field)
        if its.has("idle") {
            Section {
                Toggle(tr("Ночник между сердечками"), isOn: night)
                    .accessibilityIdentifier("nightLight")
                if its.value("idle")["brightness"] != nil {
                    LevelRow(title: tr("Яркость ночника"), value: nightLevel, range: 1...100, percent: true)
                }
            }
            .listRowBackground(Theme.field)
        }
    }

    private var night: Binding<Bool> {
        Binding(get: { its.value("idle")["brightness"] != nil }, set: { on in
            let color = Catalog.color(its.text("color")) == nil ? Catalog.pink : its.text("color")
            its.put("idle", on ? .object(["color": .string(color), "brightness": .int(10)]) : .string("off"))
        })
    }

    private var nightLevel: Binding<Double> {
        Binding(get: { Double(its.value("idle")["brightness"]?.int ?? 10) }, set: { new in
            let color = its.value("idle")["color"] ?? .string(Catalog.pink)
            its.put("idle", .object(["color": color, "brightness": .int(Int(new.rounded()))]))
        })
    }

    private func swatch(_ color: Color, picked: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 36, height: 36)
            .overlay(Circle().strokeBorder(Theme.field, lineWidth: picked ? 3 : 0))
            .overlay(Circle().stroke(Theme.ink, lineWidth: picked ? 2 : 0))
    }
}

private struct SoundPage: View {
    let its: PartSetter

    var body: some View {
        Section {
            Toggle(tr("Звук на сердечко"), isOn: its.bool("on"))
                .accessibilityIdentifier("partOn")
        }
        .listRowBackground(Theme.field)
        Section {
            if its.has("melody"), let melodies = its.part.melodies, !melodies.isEmpty {
                Chips(options: melodies, picked: its.text("melody"), name: Catalog.melody) { its.put("melody", .string($0)) }
            }
            if its.has("volume") { LevelRow(title: tr("Громкость"), value: its.level("volume"), range: 0...100, percent: true) }
        }
        .listRowBackground(Theme.field)
    }
}

private struct VibrationPage: View {
    let its: PartSetter

    var body: some View {
        Section {
            Toggle(tr("Вибрировать на сердечко"), isOn: its.bool("on"))
                .accessibilityIdentifier("partOn")
        }
        .listRowBackground(Theme.field)
        Section {
            if its.has("pattern") {
                Chips(options: ["one", "two", "heartbeat"], picked: its.text("pattern"), name: Catalog.pattern) { its.put("pattern", .string($0)) }
            }
            if its.has("strength") { LevelRow(title: tr("Сила"), value: its.level("strength"), range: 1...100, percent: true) }
        }
        .listRowBackground(Theme.field)
    }
}

private struct MotionPage: View {
    let its: PartSetter

    var body: some View {
        Section {
            Toggle(tr("Двигаться на сердечко"), isOn: its.bool("on"))
                .accessibilityIdentifier("partOn")
        }
        .listRowBackground(Theme.field)
        Section {
            if its.has("speed") { LevelRow(title: tr("Скорость"), value: its.level("speed"), range: 1...100) }
            if its.has("times") { StepRow(title: tr("Сколько раз"), value: its.int("times"), range: 1...10) { "×\($0)" } }
        }
        .listRowBackground(Theme.field)
    }
}

private struct SwitchPage: View {
    let its: PartSetter

    var body: some View {
        Section {
            Toggle(tr("Включаться на сердечко"), isOn: its.bool("on"))
                .accessibilityIdentifier("partOn")
        }
        .listRowBackground(Theme.field)
        Section {
            if its.has("mode") {
                Chips(options: ["on", "blink"], picked: its.text("mode"), name: Catalog.switchMode) { its.put("mode", .string($0)) }
            }
            if its.has("duration") {
                StepRow(title: tr("На сколько"), value: its.int("duration"), range: 1...600, text: Catalog.seconds_)
            }
        }
        .listRowBackground(Theme.field)
    }
}

private struct ScreenPage: View {
    let its: PartSetter

    var body: some View {
        Section {
            if its.has("brightness") { LevelRow(title: tr("Яркость"), value: its.level("brightness"), range: 1...100, percent: true) }
            if its.has("effect"), let effects = its.part.effects, !effects.isEmpty {
                Chips(options: effects, picked: its.text("effect"), name: Catalog.effect) { its.put("effect", .string($0)) }
            }
        } header: {
            Text(tr("Когда приходит сердечко"))
        }
        .listRowBackground(Theme.field)
        if its.has("idle_view") {
            Section(tr("Между сердечками")) {
                Chips(options: ["clock", "heart", "off"], picked: its.text("idle_view"), name: Catalog.idleView) { its.put("idle_view", .string($0)) }
            }
            .listRowBackground(Theme.field)
        }
        if its.has("sleep_after") {
            Section(tr("Гаснет через")) {
                Chips(options: ["10", "60", "300", "0"], picked: String(its.value("sleep_after").int ?? 60),
                      name: { Catalog.sleepAfter(Int($0) ?? 0) }) { its.put("sleep_after", .int(Int($0) ?? 60)) }
            }
            .listRowBackground(Theme.field)
        }
        if its.has("rotate") {
            Section(tr("Поворот")) {
                Chips(options: ["0", "90", "180", "270"], picked: String(its.value("rotate").int ?? 0),
                      name: { $0 + "°" }) { its.put("rotate", .int(Int($0) ?? 0)) }
            }
            .listRowBackground(Theme.field)
        }
        if its.has("lang") {
            Section {
                Picker(tr("Язык"), selection: Binding(get: { its.text("lang") }, set: { its.put("lang", .string($0)) })) {
                    ForEach(languages, id: \.self) { code in
                        Text(Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code).tag(code)
                    }
                }
            }
            .listRowBackground(Theme.field)
        }
    }

    /// The site's languages, and the one the screen has if it is another.
    private var languages: [String] {
        let now = its.text("lang")
        return Strings.languages.contains(now) || now.isEmpty ? Strings.languages : Strings.languages + [now]
    }
}

/// «Кнопка»: what a short, a long and a double press send. A target is a
/// signal's `to`, so the firmware pastes it as it is.
private struct ButtonPage: View {
    let its: PartSetter

    private var people: [Contact] { its.device.people(of: its.model.contacts) }

    var body: some View {
        ForEach(gestures, id: \.0) { gesture, title in
            Section {
                let target = ButtonTarget(its.value(gesture))
                choice(tr("Кому-нибудь на свете"), picked: target == .anyone, id: gesture + "-anyone") {
                    its.put(gesture, ButtonTarget.anyone.json)
                }
                choice(tr("Одному человеку"), picked: isContact(target), id: gesture + "-contact") {
                    if !isContact(target), let first = people.first { its.put(gesture, ButtonTarget.contact(first.id).json) }
                }
                .disabled(people.isEmpty)
                if case .contact(let id) = target {
                    Picker(tr("Кому"), selection: Binding(get: { id }, set: { its.put(gesture, ButtonTarget.contact($0).json) })) {
                        ForEach(shown(id)) { contact in
                            Text(contact.label).tag(contact.id)
                        }
                    }
                    .accessibilityIdentifier(gesture + "-who")
                }
                choice(tr("Ничего"), picked: target == .nothing, id: gesture + "-nothing") {
                    its.put(gesture, .null)
                }
            } header: {
                Text(title)
            } footer: {
                if gesture == gestures.last?.0 { Text(note) }
            }
            .listRowBackground(Theme.field)
            .disabled(!its.device.sends)
        }
        if its.has("confirm") {
            Section {
                Toggle(tr("Мигнуть, когда улетело"), isOn: its.bool("confirm"))
            }
            .listRowBackground(Theme.field)
        }
    }

    private var gestures: [(String, String)] {
        [("press", tr("Короткое нажатие")), ("long_press", tr("Долгое нажатие")), ("double_press", tr("Двойное нажатие"))]
            .filter { its.has($0.0) }
    }

    private var note: String {
        if !its.device.sends { return tr("Сейчас устройство не отправляет сердечки. Включить можно в «Что делает».") }
        return tr("Выбрать можно из тех, кто в списке устройства («Кто в списке»).")
    }

    private func isContact(_ target: ButtonTarget) -> Bool {
        if case .contact = target { return true }
        return false
    }

    /// The device's people, and the one picked even if the list no longer has them.
    private func shown(_ id: String) -> [Contact] {
        if people.contains(where: { $0.id == id }) { return people }
        return people + its.model.contacts.filter { $0.id == id }
    }

    private func choice(_ title: String, picked: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Theme.ink)
                Spacer()
                if picked {
                    Image(systemName: "checkmark").font(.app(15, weight: .bold)).foregroundStyle(Theme.link)
                }
            }
        }
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// One of a few: the device's effects, a melody, a pattern.
struct Chips: View {
    let options: [String]
    let picked: String
    let name: (String) -> String
    let pick: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button { pick(option) } label: {
                    Text(name(option))
                        .font(.app(14))
                        .foregroundStyle(option == picked ? Theme.paper : Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(option == picked ? Theme.ink : Theme.well, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chip-" + option)
                .accessibilityAddTraits(option == picked ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// A slider with its name and, for brightness and the like, the percent.
struct LevelRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var percent = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(Theme.ink)
            Slider(value: $value, in: range, step: 1)
                .accessibilityLabel(title)
            if percent {
                Text("\(Int(value))%")
                    .font(.app(15).monospacedDigit())
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

/// «Сколько светится − 3 с +».
struct StepRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let text: (Int) -> String

    /// Seconds up to ten minutes: by one at first, then by five, by thirty.
    private var step: Int {
        range.upperBound <= 60 ? 1 : value < 10 ? 1 : value < 60 ? 5 : 30
    }

    var body: some View {
        Stepper(value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                in: range, step: step) {
            HStack {
                Text(title).foregroundStyle(Theme.ink)
                Spacer()
                Text(text(value))
                    .font(.app(15).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

/// «Кто в списке»: the people the device itself sees, for its screen and
/// its button. Only a filter of what it is shown.
struct DeviceBookView: View {
    @EnvironmentObject var model: AppModel
    let id: String

    private var device: Device? { model.devices.first { $0.id == id } }

    var body: some View {
        Form {
            if let device {
                let book = device.book ?? .all
                Section {
                    row(tr("Все из книги"), picked: book == .all, id: "bookAll") { save(.all) }
                    row(tr("Только близкие"), picked: book == .close, id: "bookClose") { save(.close) }
                    row(tr("Выбранные"), picked: isChosen(book), id: "bookChosen") {
                        if !isChosen(book) { save(.chosen(model.closeContacts.map(\.id))) }
                    }
                } footer: {
                    Text(tr("Этих людей устройство видит: может показать их на экране и отправить им сердечко по кнопке. Остальных оно не знает."))
                }
                .listRowBackground(Theme.field)
                if case .chosen(let ids) = book {
                    Section {
                        ForEach(model.contacts) { contact in
                            row(contact.label, picked: ids.contains(contact.id), id: "bookPerson-" + contact.id) {
                                save(.chosen(ids.contains(contact.id) ? ids.filter { $0 != contact.id } : ids + [contact.id]))
                            }
                        }
                    }
                    .listRowBackground(Theme.field)
                }
            }
        }
        .tint(Theme.link)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Кто в списке"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isChosen(_ book: DeviceBook) -> Bool {
        if case .chosen = book { return true }
        return false
    }

    private func save(_ book: DeviceBook) {
        Task { await model.changeDevice(id, DeviceChange(book: book)) }
    }

    private func row(_ title: String, picked: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Theme.ink)
                Spacer()
                if picked {
                    Image(systemName: "checkmark").font(.app(15, weight: .bold)).foregroundStyle(Theme.link)
                }
            }
        }
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    static func line(_ device: Device) -> String {
        switch device.book ?? .all {
        case .all: return tr("все из книги")
        case .close: return tr("близкие")
        case .chosen(let ids): return tr("выбранные: {n}", ["n": String(ids.count)])
        }
    }
}
