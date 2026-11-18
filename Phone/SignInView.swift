import AuthenticationServices
import SwiftUI

/// Apple right here; Google and email on the site's page in Safari, which
/// comes back with lovearound://signin, as in the Mac app.
struct SignInView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 72)
                AppMark(size: 96)
                    .shadow(color: Theme.heart.opacity(0.3), radius: 18, y: 8)
                Text("Love Around")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 22)
                Text(tr("Думаешь о ком-то? Нажми, и он почувствует, что его любят и он нужен. А от кого, не узнает."))
                    .font(.system(size: 17))
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
                    Button(action: model.signInInBrowser) {
                        Label(tr("Войти через Google или почту"), systemImage: "safari")
                    }
                    .buttonStyle(WideButton(filled: false))
                    .accessibilityIdentifier("browserSignIn")
                }

                if model.busy {
                    ProgressView()
                        .padding(.top, 18)
                } else if model.waitingForBrowser {
                    VStack(spacing: 6) {
                        Text(tr("Продолжи в браузере…"))
                            .foregroundStyle(Theme.muted)
                        Button(tr("Открыть ещё раз"), action: model.signInInBrowser)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 15))
                    .padding(.top, 18)
                }
                if let problem = model.signInProblem {
                    Text(problem)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                        .accessibilityIdentifier("signInProblem")
                }
                Text(tr("Книга хранится в аккаунте"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
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
