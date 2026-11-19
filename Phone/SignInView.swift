import AuthenticationServices
import SwiftUI

/// Apple right here; Google and email on the site's page, in the system's
/// sign-in sheet over the app, which comes back with lovearound://signin.
struct SignInView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.webAuthenticationSession) private var webSignIn

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 72)
                AppMark(size: 96)
                    .shadow(color: Theme.heart.opacity(0.3), radius: 18, y: 8)
                Text("Love Around")
                    .font(.app(32, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 22)
                Text(tr("Думаешь о ком-то? Нажми, и он почувствует, что его любят и он нужен. А от кого, не узнает."))
                    .font(.app(17))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 12)
                Spacer(minLength: 56)

                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn, onRequest: model.prepareApple, onCompletion: model.appleFinished)
                        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(model.busy)
                        .accessibilityIdentifier("appleSignIn")
                    Button {
                        Task {
                            await model.signInOnSite { url in
                                try await webSignIn.authenticate(using: url, callbackURLScheme: Config.urlScheme)
                            }
                        }
                    } label: {
                        Label(tr("Войти через Google или почту"), systemImage: "envelope")
                    }
                    .buttonStyle(WideButton(filled: false))
                    .disabled(model.busy || model.waitingForBrowser)
                    .accessibilityIdentifier("browserSignIn")
                }

                if model.busy || model.waitingForBrowser {
                    ProgressView()
                        .padding(.top, 18)
                }
                if let problem = model.signInProblem {
                    Text(problem)
                        .font(.app(15))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                        .accessibilityIdentifier("signInProblem")
                }
                Text(tr("Книга хранится в аккаунте"))
                    .font(.app(13))
                    .foregroundStyle(Theme.faint)
                    .padding(.top, 28)
                Link(tr("Конфиденциальность"), destination: Config.privacyPage)
                    .font(.app(13))
                    .frame(minHeight: 44)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("privacyLink")
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.paper.ignoresSafeArea())
        .accessibilityIdentifier("signInScreen")
    }
}
