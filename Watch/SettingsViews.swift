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
