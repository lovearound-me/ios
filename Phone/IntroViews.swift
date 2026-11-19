import SwiftUI

/// Variant Б of the intro mockups (2026-11-19): what the app is for, on one
/// page. Over the app once after the first sign-in, with «Начать»; from
/// Настройки again, as a sheet, with «Понятно».
struct HowItWorksView: View {
    let button: String
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(tr("Как это работает"))
                    .font(.app(30, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 36)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                row("heart.fill", Theme.heart, tr("Нажми на человека"),
                    tr("Он почувствует, что о нём подумали: придёт уведомление, засветится экран или лампа."))
                row("eye.slash.fill", Theme.indigo, tr("От кого, не видно"),
                    tr("В сердечке нет ни имени, ни текста. Узнать, от кого оно, нельзя."))
                row("link", Theme.ok, tr("Добавь своих по Love ID"),
                    tr("Это твоя ссылка. Отправь её близким и открой их ссылки."))
                row("sparkles", Theme.star, tr("Кому-нибудь на свете"),
                    tr("Раз в час можно послать сердечко случайному человеку."))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button(button, action: close)
                .buttonStyle(WideButton(filled: true))
                .accessibilityIdentifier("howClose")
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(Theme.paper)
        }
        .background(Theme.paper.ignoresSafeArea())
        // VoiceOver stays on this page, not on the tabs under it.
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ symbol: String, _ tint: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.app(18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.app(16))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Variant В of the intro mockups: «С чего начать» on the home screen, from
/// an empty book until the first heart to someone in it. A step is crossed
/// out once done; the buttons stay while their step is open.
struct StartCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let added = !model.contacts.isEmpty
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("С чего начать"))
                .font(.app(18, weight: .bold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            StartStep(number: 1, done: model.sharedLoveID,
                      title: tr("Поделись своим Love ID."), text: tr("Это ссылка, по ней тебя добавят."))
            StartStep(number: 2, done: added,
                      title: tr("Добавь близкого по его ссылке."), text: nil)
            StartStep(number: 3, done: false,
                      title: tr("Нажми на его кружок."),
                      text: tr("Он почувствует, что о нём подумали, а от кого, не узнает."))
            if !model.sharedLoveID, model.inviteURL != nil {
                ShareLink(item: model.shareText) {
                    Text(tr("Мой Love ID"))
                }
                .buttonStyle(WideButton(filled: true))
                .simultaneousGesture(TapGesture().onEnded { model.openedShare() })
                .accessibilityIdentifier("startShare")
            }
            if !added {
                Button(tr("Добавить по ссылке")) { model.adding = AppModel.Adding(invite: "") }
                    .buttonStyle(WideButton(filled: model.sharedLoveID))
                    .accessibilityIdentifier("startAdd")
            }
        }
        .padding(18)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct StartStep: View {
    let number: Int
    let done: Bool
    let title: String
    let text: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(Theme.ok)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.paper)
                } else {
                    Circle().strokeBorder(Theme.faint, lineWidth: 1.5)
                    Text(verbatim: String(number))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.faint)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(16, weight: .semibold))
                    .foregroundStyle(done ? Theme.faint : Theme.ink)
                    .strikethrough(done, color: Theme.faint)
                if let text, !done {
                    Text(text)
                        .font(.app(15))
                        .foregroundStyle(Theme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? tr("Готово") : "")
        .accessibilityIdentifier("startStep\(number)")
    }
}
