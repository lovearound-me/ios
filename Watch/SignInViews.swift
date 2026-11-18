import AuthenticationServices
import SwiftUI

/// The app's mark: a heart on the coral-to-pink circle of the icon.
struct AppMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0xF07A62), Color(hex: 0xE86A9A)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.48))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct SignInView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                AppMark()
                Text("Love Around")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.top, 2)
                Text(tr("Тихий знак, что о тебе думают"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                SignInWithAppleButton(.signIn, onRequest: { model.prepareApple($0) }, onCompletion: { model.appleFinished($0) })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 40)
                    .padding(.top, 8)
                Button(tr("Войти по коду")) { model.startCode() }
                if let notice = model.notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.link)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .tint(Palette.link)
        }
        .disabled(model.busy)
        .overlay { if model.busy { ProgressView() } }
    }
}

/// «Войти через Apple» found the email taken by an account made with Google
/// or a password. Firebase won't join them on the watch; the code will.
struct EmailExistsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.link)
                Text(tr("Эта почта уже есть"))
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(tr("Войди по коду, и часы попадут в тот же аккаунт."))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                Button(tr("Войти по коду")) { model.startCode() }
                    .padding(.top, 6)
                Button(tr("Назад")) { model.screen = .signIn }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 2)
            }
            .tint(Palette.link)
        }
    }
}

/// Six digits with a space in the middle: 482 913.
func spaced(_ code: String) -> String {
    guard code.count == 6 else { return code }
    return String(code.prefix(3)) + " " + String(code.suffix(3))
}

/// The code screen, variant Б: the QR and the digits; the address for a
/// computer is one tap away, since every Apple Watch has an iPhone nearby.
struct CodeView: View {
    @EnvironmentObject var model: AppModel
    @State private var showComputer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 4) {
                    if let error = model.pairingError {
                        Text(error)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                        Button(tr("Ещё раз")) { model.startCode() }
                    } else if let code = model.pairing {
                        if model.pairingExpired {
                            Text(tr("Код устарел"))
                                .font(.system(size: 16, weight: .semibold))
                                .padding(.top, 10)
                            Button(tr("Новый код")) { model.startCode() }
                                .padding(.top, 6)
                        } else {
                            QRView(text: code.url)
                                .frame(width: 96, height: 96)
                            Text(spaced(code.code))
                                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                                .padding(.top, 4)
                            Text(tr("Наведи камеру iPhone"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button(tr("Ввести на компьютере")) { showComputer = true }
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.top, 4)
                        }
                    } else {
                        ProgressView().padding(.top, 30)
                    }
                }
                .frame(maxWidth: .infinity)
                .tint(Palette.link)
            }
            .navigationTitle(tr("По коду"))
            .navigationDestination(isPresented: $showComputer) {
                ComputerView(code: model.pairing?.code ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Отмена")) { model.cancelCode() }
                }
            }
        }
    }
}

/// The address and the digits, big, for typing on a computer.
struct ComputerView: View {
    let code: String

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                Text(tr("Открой"))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                Text(Config.pairingPage.replacingOccurrences(of: "/login", with: "\n/login"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.link)
                    .multilineTextAlignment(.center)
                Text(tr("и введи код"))
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 10)
                Text(spaced(code))
                    .font(.system(size: 32, weight: .semibold).monospacedDigit())
            }
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(tr("Компьютер"))
    }
}

struct ConnectedView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 52))
                .foregroundStyle(Palette.color(model.myColor))
                .symbolEffect(.pulse)
            Text(tr("Часы подключены"))
                .font(.system(size: 16, weight: .semibold))
            if let email = model.session?.email {
                Text(email)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 8)
    }
}
