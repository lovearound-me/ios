import AuthenticationServices
import SwiftUI
import UIKit

/// The pages under «Настройки», by what they set.
enum SettingsPage: Hashable {
    case account, who, glow, look, does
}

/// Variant А of the mockups, as changed on the phone (2026-11-19): one block
/// of rows like a device's card, the account first; each row opens its own
/// page, «Пауза» a menu.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var push = Push.shared
    @State private var showingHow = false

    var body: some View {
        NavigationStack(path: $model.settingsPath) {
            List {
                Section {
                    NavigationLink(value: SettingsPage.account) {
                        SettingsRow(symbol: "person.crop.circle.fill", tint: Theme.link, title: tr("Аккаунт"),
                                    sub: AccountView.shownEmail(model.email))
                    }
                    .accessibilityIdentifier("settingsAccount")
                    NavigationLink(value: SettingsPage.who) {
                        SettingsRow(symbol: "heart.fill", tint: Theme.heart, title: tr("Кто может достучаться"), sub: whoLine)
                    }
                    .accessibilityIdentifier("settingsWho")
                    NavigationLink(value: SettingsPage.glow) {
                        SettingsRow(symbol: "sun.max.fill", tint: Palette.color(model.myColor), title: tr("Как светится"),
                                    sub: Palette.all[model.myColor % Palette.all.count].name)
                    }
                    .accessibilityIdentifier("settingsGlow")
                    NavigationLink(value: SettingsPage.look) {
                        SettingsRow(symbol: "bell.fill", tint: Theme.star, title: tr("Уведомление"), sub: lookLine)
                    }
                    .accessibilityIdentifier("settingsLook")
                    NavigationLink(value: SettingsPage.does) {
                        SettingsRow(symbol: "arrow.left.arrow.right", tint: Theme.ok, title: tr("Что делает"), sub: doesLine)
                    }
                    .accessibilityIdentifier("settingsDoes")
                    pauseRow
                }
                .listRowBackground(Theme.field)
                Section {
                    Button { showingHow = true } label: {
                        HStack {
                            Text(tr("Как это работает"))
                                .font(.app(16))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.app(13, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                        }
                    }
                    .accessibilityIdentifier("settingsHow")
                    Link(destination: Config.supportPage) { pageRow(tr("Помощь")) }
                        .accessibilityIdentifier("settingsHelp")
                    Link(destination: Config.privacyPage) { pageRow(tr("Конфиденциальность")) }
                        .accessibilityIdentifier("settingsPrivacy")
                } footer: {
                    Text(verbatim: "Love Around \(model.version)")
                        .font(.app(13))
                }
                .listRowBackground(Theme.field)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(tr("Настройки"))
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .account: AccountView()
                case .who: PhoneWhoView()
                case .glow: PhoneGlowView()
                case .look: NotifyLookView()
                case .does: PhoneDoesView()
                }
            }
            .sheet(isPresented: $showingHow) {
                HowItWorksView(button: tr("Понятно")) { showingHow = false }
            }
        }
    }

    /// A page of the site, opened over the app.
    private func pageRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.app(16))
                .foregroundStyle(Theme.ink)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.app(13, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
    }

    /// A menu right on the row: three lengths, or «Снять паузу».
    private var pauseRow: some View {
        Menu {
            if model.isPaused {
                Button(tr("Снять паузу")) { model.resume() }
                    .accessibilityIdentifier("resume")
            } else {
                Button(tr("На час")) { model.pause(.hour) }
                Button(tr("До утра")) { model.pause(.untilMorning) }
                Button(tr("Пока не сниму")) { model.pause(.untilResumed) }
            }
        } label: {
            HStack {
                SettingsRow(symbol: "moon.fill", tint: Theme.indigo, title: tr("Пауза"),
                            sub: model.isPaused ? model.pauseText : tr("Нет"))
                // A menu, not a page: iOS's sign for one.
                Image(systemName: "chevron.up.chevron.down")
                    .font(.app(13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
        }
        .disabled(!model.receiveHere)
        .accessibilityIdentifier("pause")
    }

    /// «Книга и кто-нибудь на свете · тихо 23:00–08:00», as a device's.
    private var whoLine: String {
        guard model.receiveHere else { return tr("Не принимает сердечки") }
        let who = model.acceptAnyone ? tr("Книга и кто-нибудь на свете") : tr("Только книга")
        guard let quiet = model.quietHours else { return who + " · " + tr("круглые сутки") }
        return who + " · " + tr("тихо {from}–{to}", ["from": quiet.from, "to": quiet.to])
    }

    private var lookLine: String {
        guard push.status != .denied else { return tr("Выключены в настройках iPhone") }
        return model.notifyWords ? model.notifyLook.name + " · " + tr("со словами") : model.notifyLook.name
    }

    private var doesLine: String {
        model.receiveHere ? tr("Принимает и отправляет") : tr("Отправляет")
    }
}

/// «Аккаунт»: who is signed in and how, the Love ID, the ways in, signing
/// out, and at the bottom deleting it all.
struct AccountView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.authorizationController) private var apple
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.shownEmail(model.email))
                        .foregroundStyle(Theme.ink)
                    Text(signedInWith)
                        .font(.app(13))
                        .foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("account")
                if let link = model.inviteURL {
                    // The share sheet copies too: one row, not two.
                    ShareLink(item: model.shareText) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: "Love ID")
                                    .foregroundStyle(Theme.ink)
                                Text(link.replacingOccurrences(of: "https://", with: ""))
                                    .font(.app(13))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Theme.link)
                        }
                    }
                    .accessibilityLabel(tr("Поделиться своим Love ID"))
                    .accessibilityIdentifier("loveID")
                }
                Link(destination: URL(string: "https://\(Config.webApp)/#/settings/signin")!) {
                    HStack {
                        Text(tr("Способы входа"))
                            .font(.app(16))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.app(13, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                    }
                }
                Button(tr("Выйти")) { confirmSignOut = true }
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("signOut")
            } footer: {
                Text(tr("Love ID — твоя ссылка: по ней тебя добавляют в книгу. Нажми, чтобы отправить или скопировать."))
            }
            .listRowBackground(Theme.field)

            Section {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text(deleting ? tr("Удаляем…") : tr("Удалить аккаунт"))
                }
                .disabled(deleting)
                .accessibilityIdentifier("deleteAccount")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if let problem {
                        Text(problem).foregroundStyle(Theme.danger)
                    }
                    Text(tr("Вместе с книгой, устройствами и Love ID."))
                }
            }
            .listRowBackground(Theme.field)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Аккаунт"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(tr("Выйти на этом iPhone?"), isPresented: $confirmSignOut) {
            Button(tr("Выйти"), role: .destructive) { Task { await model.signOutHere() } }
            Button(tr("Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Книга останется в аккаунте."))
        }
        .alert(tr("Удалить аккаунт и весь список? Это навсегда."), isPresented: $confirmDelete) {
            Button(tr("Удалить навсегда"), role: .destructive, action: delete)
            Button(tr("Не удалять"), role: .cancel) {}
        } message: {
            if model.provider == "apple.com" {
                Text(tr("Apple попросит подтвердить, что это ты."))
            }
        }
    }

    /// Apple's relay address (…@privaterelay.appleid.com) means nothing to the person.
    static func shownEmail(_ email: String?) -> String {
        guard let email, !email.isEmpty else { return "Apple ID" }
        return email.hasSuffix("@privaterelay.appleid.com") ? tr("Почту скрыл Apple") : email
    }

    private var signedInWith: String {
        switch model.provider {
        case "apple.com": return tr("Вход через Apple")
        case "google.com": return tr("Вход через Google")
        case "password": return tr("Вход по почте")
        default: return tr("Книга хранится в аккаунте")
        }
    }

    private func delete() {
        deleting = true
        problem = nil
        Task {
            defer { deleting = false }
            do {
                var appleCode: String?
                if model.provider == "apple.com", model.demo == nil {
                    // Apple once more: with its fresh code Apple forgets the
                    // app as well. Closed by the person: nothing is deleted.
                    // Apple not answering doesn't stand in the way.
                    do {
                        let request = ASAuthorizationAppleIDProvider().createRequest()
                        request.requestedScopes = []
                        if case .appleID(let credential) = try await apple.performRequest(request) {
                            appleCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
                        }
                    } catch let error as ASAuthorizationError where error.code == .canceled {
                        return
                    } catch {}
                }
                try await model.deleteAccount(appleCode: appleCode)
            } catch {
                problem = tr("Не получилось удалить")
            }
        }
    }
}

/// A row like a device card's: a tinted symbol, a title, what it is now.
struct SettingsRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let sub: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.app(15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.app(16))
                    .foregroundStyle(Theme.ink)
                Text(sub)
                    .font(.app(13))
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// «Кто может достучаться» on this iPhone: hearts from anyone in the world,
/// and quiet hours, as on a device; here both stay on the phone and go to
/// the server only for the notifications.
struct PhoneWhoView: View {
    @EnvironmentObject var model: AppModel
    @State private var from = DeviceWhoView.date("23:00")
    @State private var to = DeviceWhoView.date("08:00")

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $model.acceptAnyone) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Кому-нибудь на свете"))
                        Text(tr("Сердечко от случайного человека"))
                            .font(.app(13))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityIdentifier("acceptAnyone")
            } footer: {
                Text(tr("Сердечки от людей из книги приходят всегда, кроме тихих часов и паузы."))
            }
            .listRowBackground(Theme.field)
            Section {
                Toggle(tr("Тихие часы"), isOn: quietOn)
                    .accessibilityIdentifier("quietHours")
                if model.quietHours != nil {
                    DatePicker(tr("с"), selection: $from, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("quietFrom")
                    DatePicker(tr("до"), selection: $to, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("quietTo")
                }
            } footer: {
                Text(note)
            }
            .listRowBackground(Theme.field)
        }
        .disabled(!model.receiveHere)
        .tint(Theme.link)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Кто может достучаться"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: from) { save() }
        .onChange(of: to) { save() }
    }

    private var quietOn: Binding<Bool> {
        Binding(get: { model.quietHours != nil }, set: { on in
            model.quietHours = on ? QuietHours(from: DeviceWhoView.hhmm(from), to: DeviceWhoView.hhmm(to),
                                               tz: TimeZone.current.identifier) : nil
        })
    }

    private func load() {
        guard let quiet = model.quietHours else { return }
        from = DeviceWhoView.date(quiet.from)
        to = DeviceWhoView.date(quiet.to)
    }

    private func save() {
        guard model.quietHours != nil else { return }
        let hours = QuietHours(from: DeviceWhoView.hhmm(from), to: DeviceWhoView.hhmm(to), tz: TimeZone.current.identifier)
        guard hours != model.quietHours, hours.from != hours.to else { return }
        model.quietHours = hours
    }

    private var note: String {
        let base = tr("В эти часы на этот iPhone сердечки не приходят и потом не придут: ни свечения, ни уведомления. Mac, часы и игрушки — как обычно, у них тихие часы свои.")
        if let tz = model.quietHours?.tz, tz != TimeZone.current.identifier {
            return base + " " + tr("Время — по часовому поясу {tz}.", ["tz": tz])
        }
        return base + " " + tr("Время — как на этом телефоне.")
    }
}

/// «Как светится»: the color of this iPhone's edges when a heart comes.
struct PhoneGlowView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                ColorSwatches(selection: $model.myColor)
            } footer: {
                Text(tr("Так светятся края экрана, когда о тебе думают."))
            }
            .listRowBackground(Theme.field)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Как светится"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// «Что делает»: this iPhone takes hearts, or only sends them.
struct PhoneDoesView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(tr("Получать сердечки на этом iPhone"), isOn: $model.receiveHere)
                    .accessibilityIdentifier("receiveHere")
            } footer: {
                Text(tr("Выключишь, и этот iPhone не засветится и не пришлёт уведомление. Mac, часы и игрушки получают как раньше. Отправлять сердечки он может всегда."))
            }
            .listRowBackground(Theme.field)
        }
        .tint(Theme.ok)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Что делает"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// «Уведомление»: how a heart's notification reads, picked by the person,
/// with a sample on a dark band as on a lock screen.
struct NotifyLookView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var push = Push.shared
    @State private var sample = NotifyLook.current.text(words: NotifyLook.withWords)

    var body: some View {
        Form {
            if push.status == .denied {
                Section {
                    Button(tr("Открыть настройки iPhone")) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text(tr("Уведомления выключены в настройках iPhone: сердечки видно, только когда приложение открыто."))
                }
                .listRowBackground(Theme.field)
            } else if push.status == .notDetermined && model.demo == nil {
                Section {
                    Button(tr("Разрешить уведомления")) { Task { await model.askForNotifications() } }
                }
                .listRowBackground(Theme.field)
            }
            Section {
                NotificationSample(text: sample)
                    .listRowInsets(EdgeInsets(top: 12, leading: 10, bottom: 12, trailing: 10))
            } header: {
                Text(tr("Так оно выглядит"))
            }
            .listRowBackground(Color(hex: 0x4A342B))
            Section {
                ForEach(NotifyLook.allCases) { look in
                    Button {
                        model.notifyLook = look
                        sample = look.text(words: model.notifyWords)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(look.name)
                                    .foregroundStyle(Theme.ink)
                                Text(look.example)
                                    .font(.app(15))
                                    .foregroundStyle(Theme.muted)
                                if let note = look.note {
                                    Text(note)
                                        .font(.app(12.5))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            Spacer()
                            if model.notifyLook == look {
                                Image(systemName: "checkmark")
                                    .font(.app(16, weight: .bold))
                                    .foregroundStyle(Theme.link)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(look.name)
                    .accessibilityAddTraits(model.notifyLook == look ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("look-\(look.rawValue)")
                }
            }
            .listRowBackground(Theme.field)
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(tr("Вибрация"))
                        Spacer()
                        Text(TapCount.words(model.taps))
                            .foregroundStyle(Theme.muted)
                            .accessibilityIdentifier("tapsWords")
                    }
                    Slider(value: Binding(get: { Double(model.taps) },
                                          set: { model.taps = Int($0.rounded()) }),
                           in: Double(TapCount.range.lowerBound)...Double(TapCount.range.upperBound),
                           step: 1) { editing in
                        // Let go: what it feels like.
                        if !editing { AppModel.playTaps(model.taps) }
                    }
                    .accessibilityLabel(tr("Вибрация"))
                    .accessibilityValue(TapCount.words(model.taps))
                    .accessibilityIdentifier("taps")
                }
            } footer: {
                Text(model.taps == 0
                     ? tr("Сердечко придёт без вибрации и без звука.")
                     : tr("Столько раз iPhone стукнет, когда сердечко приходит при открытом приложении. Когда оно закрыто, iOS вибрирует сама, один раз."))
            }
            .listRowBackground(Theme.field)
            Section {
                Toggle(isOn: $model.notifyWords) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Со словами"))
                        Text(tr("После эмодзи: «{words}»", ["words": NotifyLook.words]))
                            .font(.app(13))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityIdentifier("notifyWords")
            } footer: {
                Text(tr("Эмодзи выбирает сам iPhone, когда приходит сердечко, каждый раз новые. От кого оно, не видно ни в одном варианте. Часы и браслет показывают то же, что iPhone."))
            }
            .listRowBackground(Theme.field)
        }
        .tint(Theme.ok)
        .onChange(of: model.notifyWords) { sample = model.notifyLook.text(words: model.notifyWords) }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Уведомление"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await push.refresh() }
    }
}

/// A notification as iOS draws it on the lock screen, for the sample.
struct NotificationSample: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppMark(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: "Love Around")
                        .font(.app(15, weight: .semibold))
                    Spacer()
                    Text(tr("сейчас"))
                        .font(.app(13))
                        .foregroundStyle(Color(hex: 0x6E554A))
                }
                Text(text)
                    .font(.app(15))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color(hex: 0x3B2A23))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: 0xFFFBF6).opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notifySample")
    }
}
