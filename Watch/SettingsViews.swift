import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmSignOut = false
    // Pushed the way MainView pushes this page (navigationDestination), not
    // with NavigationLink(destination:): mixed in one stack, opening «Мой цвет»
    // kept the app busy for 24 s and more in CI's watch simulator.
    @State private var showColors = false
    @State private var showDelete = false

    var body: some View {
        List {
            Button {
                showColors = true
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(Palette.color(model.myColor)).frame(width: 14, height: 14)
                    Text(tr("Мой цвет"))
                }
            }
            .accessibilityIdentifier("myColor")
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
            Button {
                showDelete = true
            } label: {
                Text(tr("Удалить аккаунт")).foregroundStyle(.red)
            }
        }
        .navigationTitle(tr("Настройки"))
        .navigationDestination(isPresented: $showColors) { ColorPickerView() }
        .navigationDestination(isPresented: $showDelete) { DeleteAccountView() }
        .alert(tr("Выйти на этих часах?"), isPresented: $confirmSignOut) {
            Button(tr("Выйти"), role: .destructive) { model.signOut() }
            Button(tr("Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Часы останутся в «Устройствах» на {site}: убери их там.", ["site": Config.webApp]))
        }
    }
}

/// My color: the edges glow in it when someone thinks of me. Stays on this watch.
struct ColorPickerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Palette.all.indices, id: \.self) { i in
                    Button {
                        model.myColor = i
                        dismiss()
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
                }
            }
            Text(tr("Этим цветом светятся края экрана, когда кто-то о тебе думает."))
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .navigationTitle(tr("Мой цвет"))
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
                Text(tr("Удалятся твои люди, устройства и сам аккаунт. Вернуть нельзя."))
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                Text(tr("Подтверди через Apple:"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 4)
                SignInWithAppleButton(.continue, onRequest: { model.prepareApple($0) }, onCompletion: { model.deleteFinished($0) })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 40)
                if let notice = model.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.link)
                        .multilineTextAlignment(.center)
                }
                Text(tr("Входишь не через Apple? Удалить аккаунт можно на {site} → Настройки → Аккаунт.",
                        ["site": Config.webApp]))
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
