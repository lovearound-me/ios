import AuthenticationServices
import SwiftUI

/// All three ways right in the app: Apple's button, Google's own account
/// chooser, and a form for email and a password.
struct SignInView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var withEmail = false

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
                        Task { await model.signInWithGoogle() }
                    } label: {
                        Label(tr("Войти через Google"), systemImage: "g.circle.fill")
                    }
                    .buttonStyle(WideButton(filled: false))
                    .disabled(model.busy)
                    .accessibilityIdentifier("googleSignIn")
                    Button {
                        model.signInProblem = nil
                        withEmail = true
                    } label: {
                        Label(tr("Войти по почте"), systemImage: "envelope")
                    }
                    .buttonStyle(WideButton(filled: false))
                    .disabled(model.busy)
                    .accessibilityIdentifier("emailSignIn")
                }

                if model.busy && !withEmail {
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
        .sheet(isPresented: $withEmail) { EmailSignInView() }
    }
}

/// «Войти по почте»: as on the site, one button signs in, or makes the
/// account if this email has none.
struct EmailSignInView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    /// Under the buttons: what went wrong, or that the letter went.
    @State private var note: String?
    @State private var noteIsProblem = true
    @FocusState private var field: Field?

    enum Field { case email, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(tr("Почта"), text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { field = .password }
                        .accessibilityIdentifier("email")
                    SecureField(tr("Пароль"), text: $password)
                        .textContentType(.password)
                        .focused($field, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                        .accessibilityIdentifier("password")
                } footer: {
                    Text(tr("Не меньше 8 символов"))
                }
                .listRowBackground(Theme.field)
                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Text(model.busy ? tr("Входим…") : tr("Войти или создать аккаунт"))
                            Spacer()
                            if model.busy { ProgressView() }
                        }
                    }
                    .disabled(model.busy)
                    .accessibilityIdentifier("emailSubmit")
                    Button(tr("Забыли пароль?")) { forgot() }
                        .disabled(model.busy)
                        .accessibilityIdentifier("forgotPassword")
                } footer: {
                    if let note {
                        Text(note)
                            .foregroundStyle(noteIsProblem ? Theme.danger : Theme.muted)
                            .accessibilityIdentifier("emailNote")
                    }
                }
                .listRowBackground(Theme.field)
            }
            .tint(Theme.link)
            .scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle(tr("Вход по почте"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Отмена")) { dismiss() }
                }
            }
            .onAppear { field = .email }
        }
        // The sheet's own white showed under the form.
        .presentationBackground(Theme.paper)
    }

    private var address: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func say(_ text: String?, problem: Bool = true) {
        note = text
        noteIsProblem = problem
    }

    private func submit() {
        if address.isEmpty { return say(tr("Введи почту")) }
        if !address.contains("@") { return say(tr("Проверь адрес почты")) }
        if password.count < 8 { return say(tr("Пароль нужен не короче 8 символов")) }
        say(nil)
        Task {
            if let problem = await model.signInWithEmail(address, password: password) {
                say(problem)
            } else {
                dismiss()
            }
        }
    }

    private func forgot() {
        if address.isEmpty { return say(tr("Сначала введи почту")) }
        Task {
            let text = await model.sendPasswordReset(address)
            say(text, problem: text != tr("Письмо для нового пароля отправлено"))
        }
    }
}
