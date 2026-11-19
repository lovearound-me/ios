import SwiftUI
import UIKit

/// Receiving here, my color, hearts from anyone, pause, my Love ID, the account.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(tr("Получать сердечки на этом iPhone"), isOn: $model.receiveHere)
                        .accessibilityIdentifier("receiveHere")
                } footer: {
                    Text(tr("Выключишь, и этот iPhone не будет светиться. Mac, часы и игрушки получают как раньше."))
                }
                .listRowBackground(Theme.field)

                Section {
                    ColorSwatches(selection: $model.myColor)
                } header: {
                    Text(tr("Мой цвет сигнала"))
                } footer: {
                    Text(tr("Так светятся края экрана, когда о тебе думают."))
                }
                .listRowBackground(Theme.field)

                Section {
                    Toggle(tr("Сердечки от кого-нибудь на свете"), isOn: $model.acceptAnyone)
                        .disabled(!model.receiveHere)
                        .accessibilityIdentifier("acceptAnyone")
                } footer: {
                    Text(tr("Кто-то где-то нажал «Кому-нибудь на свете», и сердечко может прилететь тебе. Бывает редко, тем и приятнее."))
                }
                .listRowBackground(Theme.field)

                Section {
                    if model.isPaused {
                        HStack {
                            Text(model.pauseText)
                            Spacer()
                            Button(tr("Снять паузу")) { model.resume() }
                                .accessibilityIdentifier("resume")
                        }
                    } else {
                        Menu {
                            Button(tr("На час")) { model.pause(.hour) }
                            Button(tr("До утра")) { model.pause(.untilMorning) }
                            Button(tr("Пока не сниму")) { model.pause(.untilResumed) }
                        } label: {
                            HStack {
                                Text(tr("Пауза")).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(tr("Нет")).foregroundStyle(Theme.muted)
                            }
                        }
                        .accessibilityIdentifier("pause")
                        .disabled(!model.receiveHere)
                    }
                } footer: {
                    Text(tr("Пока сердечки приходят, только когда приложение открыто. Уведомления будут в следующей версии."))
                }
                .listRowBackground(Theme.field)

                if let link = model.inviteURL {
                    Section {
                        ShareLink(item: model.shareText) {
                            Label(tr("Поделиться своим Love ID"), systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = link
                            model.show(tr("Скопировано"))
                        } label: {
                            Label(tr("Скопировать свой Love ID"), systemImage: "doc.on.doc")
                        }
                    } header: {
                        Text(tr("Твой Love ID"))
                    } footer: {
                        Text(link)
                    }
                    .listRowBackground(Theme.field)
                }

                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shownEmail)
                            .foregroundStyle(Theme.ink)
                        Text(signedInWith)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("account")
                    Link(destination: URL(string: "https://\(Config.webApp)/#/settings/signin")!) {
                        Text(tr("Способы входа"))
                    }
                    Button(tr("Выйти")) { confirmSignOut = true }
                        .accessibilityIdentifier("signOut")
                } header: {
                    Text(tr("Аккаунт"))
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
                        Text("Love Around \(model.version)")
                    }
                }
                .listRowBackground(Theme.field)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle(tr("Настройки"))
            .alert(tr("Выйти на этом iPhone?"), isPresented: $confirmSignOut) {
                Button(tr("Выйти"), role: .destructive) { model.signOut() }
                Button(tr("Отмена"), role: .cancel) {}
            } message: {
                Text(tr("Книга останется в аккаунте."))
            }
            .alert(tr("Удалить аккаунт и весь список? Это навсегда."), isPresented: $confirmDelete) {
                Button(tr("Удалить навсегда"), role: .destructive, action: delete)
                Button(tr("Не удалять"), role: .cancel) {}
            }
        }
    }

    /// Apple's relay address (…@privaterelay.appleid.com) means nothing to the person.
    private var shownEmail: String {
        guard let email = model.email, !email.isEmpty else { return "Apple ID" }
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
                try await model.deleteAccount()
            } catch {
                problem = tr("Не получилось удалить")
            }
        }
    }
}
