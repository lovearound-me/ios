import AuthenticationServices
import SwiftUI
import WatchKit

/// The 40 mm watch (162 pt wide) and smaller: less fits before the fold.
enum Screen {
    static let small = WKInterfaceDevice.current().screenBounds.width < 170
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmSignOut = false

    var body: some View {
        List {
            if let on = model.receiving {
                Section {
                    Toggle(tr("Получать сердечки"), isOn: Binding(get: { on }, set: { model.setReceiving($0) }))
                        .accessibilityIdentifier("receiveHere")
                } footer: {
                    Text(receiveNote(on))
                }
            }
            NavigationLink {
                GlowView()
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(Palette.color(model.myColor)).frame(width: 14, height: 14)
                    Text(tr("Как светится"))
                }
            }
            .accessibilityIdentifier("glow")
            NavigationLink {
                LayoutView()
            } label: {
                SettingLine(title: tr("Вид"), value: model.layout.name)
            }
            .accessibilityIdentifier("layout")
            VStack(alignment: .leading, spacing: 2) {
                Toggle(tr("Вибрация"), isOn: $model.vibrates)
                    .accessibilityIdentifier("vibration")
                if !model.vibrates {
                    Text(tr("Сердечко придёт тихо: без тапа и без звука. Его будет видно в уведомлениях."))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle(tr("Убирать само"), isOn: $model.notificationGoes)
                    .accessibilityIdentifier("notificationGoes")
                Text(model.notificationGoes
                     ? tr("Уведомление с сердечком уйдёт с экрана через 5 секунд.")
                     : tr("Уведомление с сердечком останется, пока не закроешь его."))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let email = model.session?.email {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Аккаунт"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(email)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Button(tr("Выйти")) { confirmSignOut = true }
                .accessibilityIdentifier("signOut")
            NavigationLink {
                DeleteAccountView()
            } label: {
                Text(tr("Удалить аккаунт")).foregroundStyle(.red)
            }
        }
        .navigationTitle(tr("Настройки"))
        .alert(tr("Выйти на этих часах?"), isPresented: $confirmSignOut) {
            Button(tr("Выйти"), role: .destructive) { Task { await model.signOutHere() } }
            Button(tr("Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Часы пропадут из устройств аккаунта. Люди и аккаунт останутся."))
        }
    }

    private func receiveNote(_ on: Bool) -> String {
        if let problem = model.receiveProblem { return problem }
        if on && model.notificationsOff { return tr("Уведомления выключены. Включи их в приложении Watch на iPhone.") }
        return tr("Часы получают сердечки сами, даже если iPhone их не принимает.")
    }
}

/// A setting's name with its value under it.
private struct SettingLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// «Вид»: bubbles, circles, circles with names or a list.
struct LayoutView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(WatchLayout.allCases) { layout in
                    Button {
                        model.layout = layout
                    } label: {
                        HStack {
                            Text(layout.name)
                            Spacer(minLength: 4)
                            if model.layout == layout {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Palette.link)
                            }
                        }
                    }
                    .accessibilityIdentifier("layout-\(layout.rawValue)")
                    .accessibilityAddTraits(model.layout == layout ? .isSelected : [])
                }
            } footer: {
                Text(tr("Подержи палец на человеке, и покажется имя."))
            }
        }
        .navigationTitle(tr("Вид"))
    }
}

/// «Как светится»: my color, the one the edges glow in when someone thinks
/// of me, and a try of it. Stays on this watch.
struct GlowView: View {
    @EnvironmentObject var model: AppModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Palette.all.indices, id: \.self) { i in
                    Button {
                        model.myColor = i
                    } label: {
                        ZStack {
                            Circle().fill(Palette.color(i))
                            if i == model.myColor {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Palette.all[i].name)
                    .accessibilityAddTraits(i == model.myColor ? .isSelected : [])
                }
            }
            Button(tr("Показать")) { model.showSignal() }
                .padding(.top, 8)
                .accessibilityIdentifier("glowTry")
            Text(tr("Так светятся края экрана, когда о тебе думают."))
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .navigationTitle(tr("Как светится"))
    }
}

/// Apple asks for account deletion inside the app. Done with a fresh
/// «Войти через Apple»: the watch's own token can't delete an account, and
/// shouldn't.
struct DeleteAccountView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                // Short, so Apple's button is on the first screen of the
                // smallest watch too.
                Text(tr("Удалятся твои люди, устройства и сам аккаунт. Вернуть нельзя."))
                    .font(.system(size: Screen.small ? 12 : 13))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                SignInWithAppleButton(.continue, onRequest: { model.prepareApple($0) }, onCompletion: { model.deleteFinished($0) })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: Screen.small ? 36 : 40)
                    .padding(.top, 2)
                if let notice = model.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.link)
                        .multilineTextAlignment(.center)
                }
                Text(tr("Входишь не через Apple? Удали аккаунт в Love Around на iPhone: Настройки → Аккаунт."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
        }
        .navigationTitle(tr("Удалить аккаунт"))
        .disabled(model.busy)
    }
}
