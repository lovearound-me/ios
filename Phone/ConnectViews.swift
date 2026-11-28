import SwiftUI
import UIKit

/// The steps of «Подключить устройство».
enum ConnectStep: Hashable {
    case code, board, nearby, toyNotice, confirm, wifi, progress
}

/// Closes the whole «Подключить устройство» sheet from a page deep in it.
private struct ConnectCloseKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var connectClose: (() -> Void)? {
        get { self[ConnectCloseKey.self] }
        set { self[ConnectCloseKey.self] = newValue }
    }
}

/// A setup over Bluetooth, step by step (server docs, "Setup over
/// Bluetooth"): a board's `about` → the confirm screen → Wi-Fi → only then
/// the device on the server and its token → its first connection. A toy
/// without Wi-Fi: the note about this iPhone → pairing and its `about` →
/// the confirm screen → the device on the server, no token. A board that
/// can do both (`about.links`) asks which on the confirm screen; through the
/// phone, it is told so, restarts as a toy and is paired as one.
@MainActor
final class ConnectFlow: ObservableObject {
    enum Mark {
        case waiting, doing, done
    }

    @Published var path: [ConnectStep] = []
    /// The row being connected to.
    @Published var connectingTo: UUID?
    @Published var problem: String?
    @Published var picked: ToyCenter.Found?
    @Published var about: DeviceAbout?
    @Published var name = ""
    @Published var networks: [WifiNetwork] = []
    @Published var lookingForNetworks = false
    @Published var ssid = ""
    @Published var otherNetwork = false
    @Published var password = ""
    @Published var wifiProblem: String?
    @Published var marks: [Mark] = [.waiting, .waiting, .waiting]
    @Published var failed: String?
    @Published var made: Device?
    @Published var pairing = false
    /// A board that can do both: through this iPhone rather than its own Wi-Fi.
    @Published var throughPhone = false

    /// Set up again: the same device, a new token.
    let again: Device?
    private(set) var raw: [String: Any] = [:]
    private var link: BoardLink?
    private var running = false

    init(again: Device?) {
        self.again = again
        if let again { name = again.name }
    }

    var isToy: Bool { picked?.toy == true }
    /// Ends up a toy this iPhone talks for: one already, or a board switched.
    var asToy: Bool { isToy || throughPhone }
    /// The board said it can go either way.
    var offersChoice: Bool {
        guard !isToy, let links = about?.links else { return false }
        return links.contains("server") && links.contains("phone")
    }
    /// The toy a switched board became, once found.
    private var switchedToy: UUID?
    var finished: Bool { marks.allSatisfy { $0 == .done } }

    /// A row of the search was tapped.
    func pick(_ found: ToyCenter.Found, model: AppModel) {
        guard connectingTo == nil else { return }
        problem = nil
        picked = found
        if found.toy {
            path.append(.toyNotice)
            return
        }
        connectingTo = found.id
        Task {
            defer { connectingTo = nil }
            let link: BoardLink = model.demo != nil ? DemoBoardLink() : ESPBoardLink(name: found.name)
            do {
                try await link.connect()
                take(try await link.about(), fallback: found.name)
                self.link?.close()
                self.link = link
                model.toys.stopSearch()
                path.append(.confirm)
            } catch {
                link.close()
                problem = (error as? LocalizedError)?.errorDescription ?? tr("Не получилось, попробуй ещё раз")
            }
        }
    }

    /// «Понятно, дальше»: iOS asks to pair, the toy says what it is.
    func pairToy(model: AppModel) {
        guard let picked, !pairing else { return }
        pairing = true
        problem = nil
        Task {
            defer { pairing = false }
            do {
                take(try await model.toys.pair(picked.id), fallback: picked.name)
                model.toys.stopSearch()
                path.append(.confirm)
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? tr("Не получилось, попробуй ещё раз")
            }
        }
    }

    private func take(_ about: [String: Any], fallback: String) {
        raw = about
        let data = (try? JSONSerialization.data(withJSONObject: about)) ?? Data()
        self.about = (try? JSONDecoder().decode(DeviceAbout.self, from: data)) ?? DeviceAbout()
        if again == nil, name.isEmpty {
            name = self.about?.model ?? fallback
        }
    }

    func lookForNetworks() {
        guard let link, !lookingForNetworks else { return }
        lookingForNetworks = true
        Task {
            defer { lookingForNetworks = false }
            networks = (try? await link.networks()) ?? []
            if ssid.isEmpty, let first = networks.first { ssid = first.ssid }
            if networks.isEmpty { otherNetwork = true }
        }
    }

    var chosenSecured: Bool {
        otherNetwork || networks.first { $0.ssid == ssid }?.secured ?? true
    }

    /// Wi-Fi first; the device on the server and its token only once the
    /// board has joined; then Bluetooth is let go and the board's first
    /// connection awaited. Whatever fails before that leaves no device.
    func connectBoard(model: AppModel) {
        guard let link, !running else { return }
        running = true
        failed = nil
        wifiProblem = nil
        marks = [.doing, .waiting, .waiting]
        path.append(.progress)
        let ssid = ssid.trimmingCharacters(in: .whitespaces)
        Task {
            defer { running = false }
            do {
                try await link.join(ssid: ssid, password: chosenSecured ? password : "")
            } catch {
                // Back to Wi-Fi: nothing was made yet.
                wifiProblem = (error as? LocalizedError)?.errorDescription ?? SetupError.wifi.errorDescription
                if path.last == .progress { path.removeLast() }
                return
            }
            marks = [.done, .doing, .waiting]
            var device: Device?
            do {
                let token: String
                if let again {
                    token = try await model.newDeviceToken(again)
                    device = again
                } else {
                    let made = try await model.makeBoard(name: trimmedName, about: raw)
                    (device, token) = (made.0, made.1)
                }
                // The board drops Bluetooth once it has the token, and its
                // answer can be lost with the link: then only its coming
                // online tells whether it got it.
                var heard = true
                do {
                    try await link.send(token: token)
                } catch SetupError.connection {
                    heard = false
                } catch {
                    throw SetupError.token
                }
                guard let device else { throw SetupError.token }
                model.rememberWifi(device.id, ssid)
                marks = [.done, .done, .doing]
                // Bluetooth is freed before the board's first TLS connection.
                link.close()
                self.link = nil
                guard await model.waitOnline(device.id) else { throw heard ? SetupError.neverOnline : SetupError.token }
                marks = [.done, .done, .done]
                made = model.devices.first { $0.id == device.id } ?? device
            } catch {
                link.close()
                self.link = nil
                if again == nil, let device { await model.dropUnfinished(device.id) }
                failed = message(error)
            }
        }
    }

    /// Through this iPhone: the board is told so over its setup link, comes
    /// back a few seconds later as a Bluetooth toy (its own address, the same
    /// name), and is paired and added like any toy. Set up again, the old
    /// device goes once the new one is in.
    func connectThroughPhone(model: AppModel) {
        guard let link, let picked, !running else { return }
        running = true
        failed = nil
        marks = [.doing, .waiting, .waiting]
        path.append(.progress)
        Task {
            defer { running = false }
            do {
                try await link.sendPhoneLink()
                link.close()
                self.link = nil
                let toy = try await findSwitched(picked.name, model: model)
                switchedToy = toy
                let said = try await model.toys.pair(toy)
                if model.demo == nil { take(said, fallback: picked.name) }
                model.toys.stopSearch()
                marks = [.done, .doing, .waiting]
                let device = try await model.makeToy(name: trimmedName, about: raw, peripheral: toy)
                if let again { await model.removeDevice(again) }
                marks = [.done, .done, .done]
                made = device
            } catch {
                link.close()
                self.link = nil
                failed = message(error)
            }
        }
    }

    /// The board again, now advertising the toy service under its name.
    private func findSwitched(_ name: String, model: AppModel) async throws -> UUID {
        if model.demo != nil {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            return ToyCenter.demoToy
        }
        model.toys.search()
        for _ in 0..<100 {
            if let toy = model.toys.found.first(where: { $0.toy && $0.name == name }) { return toy.id }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        model.toys.stopSearch()
        throw SetupError.notFound
    }

    func connectToy(model: AppModel) {
        guard let picked, !running else { return }
        running = true
        failed = nil
        marks = [.done, .doing, .waiting]
        path.append(.progress)
        Task {
            defer { running = false }
            do {
                let device = try await model.makeToy(name: trimmedName, about: raw, peripheral: picked.id)
                marks = [.done, .done, .done]
                made = device
            } catch {
                failed = message(error)
            }
        }
    }

    private var trimmedName: String {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        return trimmed.isEmpty ? tr("Устройство") : trimmed
    }

    private func message(_ error: Error) -> String {
        if case APIError.status(409, "too many devices") = error { return tr("Устройств уже много, отключи лишние") }
        return (error as? LocalizedError)?.errorDescription ?? tr("Не получилось, попробуй ещё раз")
    }

    /// From the start: the search again.
    func startOver(model: AppModel) {
        link?.close()
        link = nil
        failed = nil
        problem = nil
        if let switchedToy, made == nil { model.toys.drop(switchedToy) }
        switchedToy = nil
        throughPhone = false
        picked = nil
        about = nil
        password = ""
        marks = [.waiting, .waiting, .waiting]
        path = again == nil ? [.nearby] : []
        model.toys.search()
    }

    /// The sheet closed, finished or not.
    func leave(model: AppModel) {
        link?.close()
        link = nil
        model.toys.stopSearch()
        if let picked, picked.toy, made == nil { model.toys.drop(picked.id) }
        if let switchedToy, made == nil { model.toys.drop(switchedToy) }
    }

    /// A demo's screenshot of one step.
    func demo(_ step: String, model: AppModel) {
        let board = ToyCenter.Found(id: ToyCenter.demoBoard, name: DemoBoardLink.name, rssi: -48, toy: false)
        let toy = ToyCenter.Found(id: ToyCenter.demoToy, name: Demo.said("Браслет «Пульс»", "Pulse band"), rssi: -66, toy: true)
        switch step {
        case "nearby":
            path = [.nearby]
        case "confirmBoard", "wifi", "connected":
            picked = board
            link = DemoBoardLink()
            take(DemoBoardLink.about, fallback: board.name)
            name = Demo.ring().name
            path = [.nearby, .confirm]
            if step != "confirmBoard" {
                path.append(.wifi)
                password = DemoBoardLink.password
            }
            if step == "connected" {
                ssid = "Casa-Lisboa"
                path.append(.progress)
                marks = [.done, .done, .done]
                made = model.devices.first { $0.id == Demo.ring().id }
            }
        case "toyNotice":
            picked = toy
            path = [.nearby, .toyNotice]
        default:
            break
        }
    }
}

/// «Подключить устройство»: three ways in, the nearest first.
struct ConnectView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flow: ConnectFlow
    private let demoStep: String?

    init(_ connecting: AppModel.Connecting) {
        _flow = StateObject(wrappedValue: ConnectFlow(again: connecting.again))
        demoStep = connecting.demoStep
    }

    var body: some View {
        NavigationStack(path: $flow.path) {
            Group {
                if flow.again == nil {
                    ways
                } else {
                    NearbyView()
                }
            }
            .navigationDestination(for: ConnectStep.self) { step in
                switch step {
                case .code: PairView(code: "")
                case .board: BoardView()
                case .nearby: NearbyView()
                case .toyNotice: ToyNoticeView()
                case .confirm: ConfirmDeviceView()
                case .wifi: WifiView()
                case .progress: ConnectProgressView()
                }
            }
        }
        .environmentObject(flow)
        .environment(\.connectClose) { dismiss() }
        .interactiveDismissDisabled(flow.path.last == .progress && !flow.finished && flow.failed == nil)
        .onAppear {
            if let demoStep { flow.demo(demoStep, model: model) }
        }
        .onDisappear { flow.leave(model: model) }
    }

    private var ways: some View {
        List {
            Section {
                Text(tr("Игрушка, лампа или своя плата, которая светится, когда о тебе думают, или отправляет сердечко по кнопке."))
                    .font(.app(15))
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink(value: ConnectStep.nearby) {
                    way("dot.radiowaves.left.and.right", tint: Theme.link, title: tr("Рядом, по Bluetooth"),
                        sub: tr("Устройство рядом с тобой. Wi-Fi передадим ему сами"), best: true)
                }
                .accessibilityIdentifier("connectNearby")
                NavigationLink(value: ConnectStep.code) {
                    way("number", tint: Theme.ink, title: tr("Код на шесть цифр"), sub: tr("Часы и лампы, у которых есть экран"))
                }
                .accessibilityIdentifier("pairByCode")
                NavigationLink(value: ConnectStep.board) {
                    way("chevron.left.forwardslash.chevron.right", tint: Theme.ink, title: tr("Своя плата с токеном"),
                        sub: tr("Токен вставляют в прошивку вручную"))
                }
                .accessibilityIdentifier("addBoard")
            } header: {
                Text(tr("Как подключить"))
            } footer: {
                Text(tr("По Bluetooth подключаются и платы с Wi-Fi, и игрушки без него: такие получают сердечки через этот телефон."))
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
        .navigationTitle(tr("Подключить устройство"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(tr("Отмена")) { dismiss() }
            }
        }
    }

    private func way(_ symbol: String, tint: Color, title: String, sub: String, best: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.app(15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.app(17))
                    .foregroundStyle(Theme.ink)
                Text(sub)
                    .font(.app(13))
                    .foregroundStyle(Theme.muted)
                if best {
                    Text(tr("Проще всего"))
                        .font(.app(12, weight: .semibold))
                        .foregroundStyle(Theme.ok)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.ok.opacity(0.14), in: Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// «Ищем рядом»: Love Around devices in setup mode, only the very near.
struct NearbyView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var flow: ConnectFlow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NearbyList(toys: model.toys)
            .navigationTitle(flow.again == nil ? tr("Ищем рядом") : tr("Настроить заново"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if flow.again != nil {
                        Button(tr("Отмена")) { dismiss() }
                    }
                }
            }
            .onAppear {
                if flow.path.last == .nearby || flow.path.isEmpty { model.toys.search() }
            }
    }
}

private struct NearbyList: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var flow: ConnectFlow
    @ObservedObject var toys: ToyCenter
    @State private var showingSample = false

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "button.programmable")
                        .font(.app(26))
                        .foregroundStyle(Theme.link)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("Зажми кнопку на устройстве на 3 секунды, пока оно не замигает. Так его будет видно 5 минут."))
                            .font(.app(15))
                            .foregroundStyle(Theme.ink)
                        Text(tr("Новое устройство видно сразу, кнопка не нужна."))
                            .font(.app(14))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.well)
            }
            Section {
                switch toys.radio {
                case .off:
                    Text(tr("Bluetooth выключен. Включи его в Пункте управления."))
                        .foregroundStyle(Theme.danger)
                case .denied:
                    Text(tr("Love Around не может пользоваться Bluetooth. Разреши это в настройках iPhone."))
                        .foregroundStyle(Theme.danger)
                    Button(tr("Открыть настройки")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                case .unsupported:
                    Text(tr("На этом устройстве нет Bluetooth."))
                        .foregroundStyle(Theme.muted)
                default:
                    if toys.found.isEmpty {
                        Text(tr("Пока никого. Поднеси телефон к устройству."))
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(toys.found) { found in
                        Button { flow.pick(found, model: model) } label: { row(found) }
                            .disabled(flow.connectingTo != nil)
                            .accessibilityIdentifier(found.toy ? "nearbyToy" : "nearbyBoard")
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text(tr("Устройства рядом"))
                    if toys.radio == .on || toys.radio == .unknown { ProgressView().controlSize(.small) }
                }
            } footer: {
                if let problem = flow.problem {
                    Text(problem).foregroundStyle(Theme.danger)
                } else {
                    Text(tr("Показываем только устройства Love Around, которые сейчас ждут настройки, и только совсем близкие."))
                }
            }
            .listRowBackground(Theme.field)
            if model.offersSample, flow.again == nil {
                Section {
                    Button {
                        showingSample = true
                    } label: {
                        Label(tr("Посмотреть на примере"), systemImage: "play.circle")
                    }
                    .accessibilityIdentifier("openSample")
                } footer: {
                    Text(tr("Нет устройства под рукой? В примере плата и игрушка выдуманные: можно пройти все шаги и поменять настройки. Только в тестовых сборках."))
                }
                .listRowBackground(Theme.field)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .fullScreenCover(isPresented: $showingSample) { SampleView() }
    }

    private func row(_ found: ToyCenter.Found) -> some View {
        HStack(spacing: 14) {
            Image(systemName: found.toy ? "heart.fill" : "cpu")
                .font(.app(18))
                .foregroundStyle(found.toy ? Theme.heart : Theme.muted)
                .frame(width: 40, height: 40)
                .background(found.toy ? Theme.heartSoft : Theme.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(found.name)
                    .font(.app(17))
                    .foregroundStyle(Theme.ink)
                Text((found.toy ? tr("Игрушка без Wi-Fi") : tr("Плата с Wi-Fi")) + " · "
                     + (found.veryNear ? tr("совсем рядом") : tr("в паре метров")))
                    .font(.app(13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            if flow.connectingTo == found.id {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Before a toy without Wi-Fi pairs: what it needs from this iPhone, and
/// what iOS is about to ask.
struct ToyNoticeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var flow: ConnectFlow

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .font(.app(26))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 56, height: 56)
                            .background(Theme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.muted)
                        Image(systemName: "heart.fill")
                            .font(.app(26))
                            .foregroundStyle(Theme.heart)
                            .frame(width: 56, height: 56)
                            .background(Theme.heartSoft, in: Circle())
                    }
                    Text(flow.picked?.name ?? "")
                        .font(.app(24, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                    Text(tr("У него нет Wi-Fi. Сердечки ему будет передавать этот iPhone."))
                        .font(.app(15))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)
            Section(tr("Сердечки дойдут, когда")) {
                Label(tr("Телефон рядом, в нескольких метрах"), systemImage: "wifi")
                Label(tr("Уведомления Love Around на iPhone включены"), systemImage: "bell")
                Label(tr("Тихие часы и пауза — как у этого телефона"), systemImage: "moon")
            }
            .listRowBackground(Theme.field)
            Section {
                Label {
                    Text(tr("Сейчас iOS спросит, можно ли устройству видеть уведомления. Оно смотрит только на уведомления Love Around, чужие не читает."))
                        .font(.app(14))
                } icon: {
                    Image(systemName: "shield")
                }
                .foregroundStyle(Theme.ok)
                .listRowBackground(Theme.ok.opacity(0.14))
            } footer: {
                if let problem = flow.problem {
                    Text(problem).foregroundStyle(Theme.danger)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { flow.pairToy(model: model) } label: {
                if flow.pairing {
                    ProgressView().tint(Theme.onLink)
                } else {
                    Text(tr("Понятно, дальше"))
                }
            }
            .buttonStyle(WideButton(filled: true))
            .disabled(flow.pairing)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Theme.paper)
            .accessibilityIdentifier("toyNoticeNext")
        }
    }
}

/// What the device is and what it asks for, before anything is made.
struct ConfirmDeviceView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var flow: ConnectFlow

    private var about: DeviceAbout { flow.about ?? DeviceAbout() }
    private var wants: [String] { about.wants ?? ["receive"] }

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.app(34))
                        .foregroundStyle(Theme.heart)
                        .frame(width: 72, height: 72)
                        .background(Theme.heartSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text(about.model ?? flow.picked?.name ?? "")
                        .font(.app(24, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.app(14))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Color.clear)
            Section {
                if wants.contains("receive") {
                    want(tr("Получать сердечки"), tr("Отзывается, когда о тебе думают"))
                }
                if wants.contains("send") {
                    want(tr("Отправлять сердечки"), tr("По кнопке. Увидит имена близких из твоей книги"))
                }
            } header: {
                Text(tr("Оно хочет"))
            } footer: {
                Text(tr("Потом это можно только сузить в карточке устройства."))
            }
            .listRowBackground(Theme.field)
            if !about.shownParts.isEmpty {
                Section(tr("Из чего оно")) {
                    FlowLayout(spacing: 8) {
                        ForEach(about.shownParts) { part in
                            Text(chip(part))
                                .font(.app(15))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.well, in: Capsule())
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            if flow.offersChoice {
                Section {
                    way(phone: false, tr("По Wi-Fi"), tr("Работает само, даже когда тебя нет рядом"), symbol: "wifi")
                    way(phone: true, tr("Через этот iPhone"), tr("Без Wi-Fi: сердечки идут через телефон, пока он рядом"),
                        symbol: "iphone.radiowaves.left.and.right")
                } header: {
                    Text(tr("Как ему связываться"))
                } footer: {
                    Text(tr("Поменять потом можно, только подключив его заново."))
                }
                .listRowBackground(Theme.field)
            }
            if flow.again == nil {
                Section(tr("Название")) {
                    TextField(tr("Например, Котик на полке"), text: $flow.name)
                        .accessibilityIdentifier("connectName")
                }
                .listRowBackground(Theme.field)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(flow.asToy ? tr("Подключить") : tr("Дальше: Wi-Fi")) {
                    if flow.isToy {
                        flow.connectToy(model: model)
                    } else if flow.throughPhone {
                        flow.connectThroughPhone(model: model)
                    } else {
                        flow.path.append(.wifi)
                    }
                }
                .buttonStyle(WideButton(filled: true))
                .accessibilityIdentifier("confirmDevice")
                Text(tr("Подключай только своё устройство, которое стоит перед тобой."))
                    .font(.app(13))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Theme.paper)
        }
    }

    private var subtitle: String {
        let firmware = about.firmware.map { tr("Прошивка {version}", ["version": $0]) }
        let link = flow.offersChoice ? nil : flow.isToy ? tr("через этот iPhone") : tr("через Wi-Fi")
        return [firmware, link].compactMap { $0 }.joined(separator: " · ")
    }

    private func way(phone: Bool, _ title: String, _ sub: String, symbol: String) -> some View {
        Button {
            flow.throughPhone = phone
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.app(20))
                    .foregroundStyle(Theme.link)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(17))
                        .foregroundStyle(Theme.ink)
                    Text(sub)
                        .font(.app(14))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: flow.throughPhone == phone ? "checkmark.circle.fill" : "circle")
                    .font(.app(22))
                    .foregroundStyle(flow.throughPhone == phone ? Theme.link : Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(phone ? "linkPhone" : "linkWifi")
        .accessibilityAddTraits(flow.throughPhone == phone ? .isSelected : [])
    }

    private func chip(_ part: DevicePart) -> String {
        let title = about.title(part)
        if part.known == .light, let leds = part.leds, leds > 1 { return title + " · " + tr("светодиодов: {n}", ["n": String(leds)]) }
        return title
    }

    private func want(_ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.app(22))
                .foregroundStyle(Theme.link)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(17))
                    .foregroundStyle(Theme.ink)
                Text(sub)
                    .font(.app(14))
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Wi-Fi»: the networks the board itself sees, and the password, which
/// goes straight to the board, encrypted.
struct WifiView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var flow: ConnectFlow
    @State private var shown = false

    private var ready: Bool {
        let named = !flow.ssid.trimmingCharacters(in: .whitespaces).isEmpty
        return named && (!flow.chosenSecured || flow.password.count >= 8)
    }

    var body: some View {
        List {
            Section {
                Text(tr("Через какую сеть «{name}» будет выходить в интернет. Эти сети оно видит само.", ["name": flow.name]))
                    .font(.app(15))
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
            Section {
                if flow.lookingForNetworks && flow.networks.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(tr("Устройство ищет сети…")).foregroundStyle(Theme.muted)
                    }
                }
                ForEach(flow.networks) { network in
                    Button {
                        flow.otherNetwork = false
                        flow.ssid = network.ssid
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.app(15, weight: .bold))
                                .foregroundStyle(Theme.link)
                                .opacity(!flow.otherNetwork && flow.ssid == network.ssid ? 1 : 0)
                            Text(network.ssid)
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if network.secured {
                                Image(systemName: "lock.fill").font(.app(12))
                            }
                            Image(systemName: "wifi", variableValue: Double(network.bars) / 4)
                        }
                        .foregroundStyle(Theme.muted)
                    }
                    .accessibilityIdentifier("wifi-" + network.ssid)
                }
                Button(tr("Другая сеть…")) {
                    flow.otherNetwork = true
                    flow.ssid = ""
                }
                if flow.otherNetwork {
                    TextField(tr("Название сети"), text: $flow.ssid)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wifiName")
                }
            } header: {
                Text(tr("Сети рядом с устройством"))
            } footer: {
                Text(tr("Видны только сети 2,4 ГГц: сети 5 ГГц такие платы не ловят."))
            }
            .listRowBackground(Theme.field)
            if flow.chosenSecured {
                Section {
                    HStack {
                        Group {
                            if shown {
                                TextField(tr("Пароль"), text: $flow.password)
                            } else {
                                SecureField(tr("Пароль"), text: $flow.password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("wifiPassword")
                        Button { shown.toggle() } label: {
                            Image(systemName: shown ? "eye.slash" : "eye")
                                .foregroundStyle(Theme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(shown ? tr("Скрыть пароль") : tr("Показать пароль"))
                    }
                } header: {
                    Text(flow.ssid.isEmpty ? tr("Пароль") : tr("Пароль от {name}", ["name": flow.ssid]))
                } footer: {
                    if let problem = flow.wifiProblem {
                        Text(problem).foregroundStyle(Theme.danger)
                    }
                }
                .listRowBackground(Theme.field)
            } else if let problem = flow.wifiProblem {
                Section { Text(problem).foregroundStyle(Theme.danger) }
                    .listRowBackground(Theme.field)
            }
            Section {
                Label {
                    Text(tr("Пароль уходит прямо в устройство, зашифрованным. На наш сервер он не попадает."))
                        .font(.app(14))
                } icon: {
                    Image(systemName: "shield")
                }
                .foregroundStyle(Theme.ok)
                .listRowBackground(Theme.ok.opacity(0.14))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle("Wi-Fi")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(tr("Подключить")) { flow.connectBoard(model: model) }
                .buttonStyle(WideButton(filled: true))
                .disabled(!ready)
                .opacity(ready ? 1 : 0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .background(Theme.paper)
                .accessibilityIdentifier("wifiConnect")
        }
        .onAppear {
            if flow.networks.isEmpty { flow.lookForNetworks() }
        }
    }
}

/// The last step: what is done and what is being done; then «Проверить»
/// and «Настроить».
struct ConnectProgressView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var flow: ConnectFlow
    @Environment(\.connectClose) private var close

    private var steps: [String] {
        if flow.asToy {
            return [tr("Связались по Bluetooth"), tr("Добавлено в твой аккаунт"), tr("Настройки записаны в устройство")]
        }
        let joined = flow.ssid.isEmpty ? tr("Подключилось к Wi-Fi") : tr("Подключилось к {name}", ["name": flow.ssid])
        return [joined, flow.again == nil ? tr("Добавлено в твой аккаунт") : tr("Получило новый ключ"), tr("Вышло на связь")]
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.app(44))
                        .foregroundStyle(Theme.heart)
                        .frame(width: 96, height: 96)
                        .background(Theme.heartSoft, in: Circle())
                    Text(flow.finished ? tr("«{name}» подключено", ["name": flow.name]) : tr("Подключаем «{name}»…", ["name": flow.name]))
                        .font(.app(24, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("connectTitle")
                    if flow.finished {
                        Text(flow.asToy ? tr("Сердечки ему будет передавать этот iPhone, пока он рядом.")
                             : tr("Теперь оно в сети само, телефон ему больше не нужен."))
                            .font(.app(15))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                    HStack(spacing: 12) {
                        mark(flow.marks[i])
                        Text(text)
                            .foregroundStyle(flow.marks[i] == .waiting ? Theme.muted : Theme.ink)
                    }
                }
            } footer: {
                if let failed = flow.failed {
                    Text(failed).foregroundStyle(Theme.danger)
                } else if !flow.asToy, !flow.finished {
                    Text(tr("Не подошёл пароль? Вернём на шаг с Wi-Fi, а в аккаунте ничего лишнего не останется."))
                }
            }
            .listRowBackground(Theme.field)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if flow.finished {
                    Button(tr("Готово")) { close?() }
                        .accessibilityIdentifier("connectDone")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                if flow.failed != nil {
                    Button(tr("Отмена")) { close?() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if flow.finished, let device = flow.made {
                    Button {
                        Task { await model.preview(model.devices.first { $0.id == device.id } ?? device) }
                    } label: {
                        Label(tr("Проверить"), systemImage: "heart.fill")
                    }
                    .buttonStyle(WideButton(filled: false))
                    .accessibilityIdentifier("connectPreview")
                    Button(tr("Настроить")) {
                        model.tab = .toys
                        model.toysPath = [device.id]
                        close?()
                    }
                    .buttonStyle(WideButton(filled: true))
                    .accessibilityIdentifier("connectSetUp")
                } else if flow.failed != nil {
                    Button(tr("Начать заново")) { flow.startOver(model: model) }
                        .buttonStyle(WideButton(filled: true))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Theme.paper)
        }
    }

    @ViewBuilder
    private func mark(_ mark: ConnectFlow.Mark) -> some View {
        switch mark {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.app(20))
                .foregroundStyle(Theme.ok)
        case .doing:
            ProgressView().frame(width: 22, height: 22)
        case .waiting:
            Image(systemName: "circle")
                .font(.app(20))
                .foregroundStyle(Theme.faint)
        }
    }
}

/// Chips that wrap onto the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for (subview, point) in zip(subviews, rows.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, widest, y + line)
    }
}

/// A TestFlight or a debug build, not the App Store's.
enum Build {
    static let isTest: Bool = {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()
}

/// The whole app on a made-up account, over the real one: a tester without
/// a board or a toy connects made-up ones and turns their settings. Nothing
/// here reaches the network, the radio or the real account.
struct SampleView: View {
    @StateObject private var sample = AppModel(sample: true)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RootView()
            .environmentObject(sample)
            .tint(Theme.link)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "theatermasks")
                    Text(tr("Это пример: люди и устройства выдуманные"))
                        .font(.app(13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(tr("Закрыть")) { dismiss() }
                        .font(.app(13, weight: .semibold))
                        .accessibilityIdentifier("closeSample")
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.star.opacity(0.22))
                .background(Theme.paper)
            }
    }
}
