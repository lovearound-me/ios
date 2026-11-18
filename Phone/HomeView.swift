import SwiftUI

/// Variant Б of the mockups: the big heart for «Кому-нибудь на свете», then
/// the close people in circles, three to a row, then the whole book.
struct HomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                banners
                AnyoneHeart()
                    .frame(maxWidth: .infinity)
                if model.contacts.isEmpty {
                    if model.loaded { EmptyBook() }
                } else {
                    people
                    Button { model.tab = .book } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "book.closed")
                                .foregroundStyle(Theme.muted)
                            Text(tr("Вся книга · {n}", ["n": String(model.contacts.count)]))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                        }
                        .font(.system(size: 16))
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wholeBook")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .refreshable { await model.reload() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.heart)
                Text("Love Around")
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.ink)
            }
            .font(.system(size: 17))
            Spacer()
            Button { model.adding = AppModel.Adding(invite: "") } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.well, in: Circle())
            }
            .accessibilityLabel(tr("Добавить по ссылке"))
            .accessibilityIdentifier("addByLink")
        }
    }

    @ViewBuilder private var banners: some View {
        if model.isPaused {
            Banner(text: tr("{pause}. Сигналы не придут.", ["pause": model.pauseText]),
                   action: tr("Снять паузу"), symbol: "moon.fill") { model.resume() }
        }
        if model.offline {
            Banner(text: tr("Нет связи с сервером, сигналы сейчас не приходят. Переподключаемся…"),
                   action: nil, symbol: "wifi.slash") {}
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.closeContacts.isEmpty ? tr("Книга") : tr("Рядом"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 16) {
                ForEach(model.homeCircles) { contact in
                    Button { model.send(contact) } label: {
                        PersonCircle(contact: contact, sent: model.justSent == contact.id)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(contact.label)
                    .accessibilityHint(tr("Отправить сердечко"))
                }
            }
        }
    }
}

/// The big heart: a signal to one random person, once an hour.
struct AnyoneHeart: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let wait = model.anyoneWait(at: context.date)
            let sent = model.justSent == AppModel.anyoneID
            VStack(spacing: 10) {
                Button(action: model.sendToAnyone) {
                    ZStack {
                        Circle()
                            .fill(Theme.heartSoft)
                            .frame(width: 168, height: 168)
                            .background(Circle().fill(Theme.heartSoft.opacity(0.5)).padding(-10))
                            .shadow(color: Theme.heart.opacity(0.28), radius: 17, y: 14)
                        Image(systemName: sent ? "sparkles" : "heart.fill")
                            .font(.system(size: sent ? 72 : 88))
                            .foregroundStyle(sent ? Theme.star : Theme.heart)
                            .symbolEffect(.bounce, value: sent)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .opacity(wait != nil && !sent ? 0.55 : 1)
                }
                .buttonStyle(PressScale())
                .disabled(wait != nil)
                .accessibilityLabel(tr("Кому-нибудь на свете"))
                .accessibilityIdentifier("anyone")
                Text(tr("Кому-нибудь на свете"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 8)
                Text(wait.map { tr("Кому-нибудь — через {n} мин", ["n": String($0)]) }
                     ?? tr("Сигнал уйдёт случайному человеку, раз в час. Он не узнает, от кого."))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
                    .accessibilityIdentifier("anyoneNote")
            }
            .padding(.top, 16)
        }
    }
}

/// A person's circle: their color as a ring and a tint, the initial inside;
/// filled with a heart for a moment once a signal went.
struct PersonCircle: View {
    let contact: Contact
    var sent = false
    var size: CGFloat = 76
    var named = true

    var body: some View {
        let color = Palette.color(contact.color)
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(sent ? color : color.opacity(0.2))
                Circle()
                    .strokeBorder(color, lineWidth: 3)
                if sent {
                    Image(systemName: "heart.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text(initial)
                        .font(.system(size: size * 0.37, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(width: size, height: size)
            .animation(.spring(duration: 0.3), value: sent)
            if named {
                Text(contact.label)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
        }
    }

    private var initial: String {
        contact.label.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "♥"
    }
}

/// Nobody in the book yet: how people get in.
struct EmptyBook: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Добавь людей по их ссылке или поделись своим Love ID."))
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                Button(tr("Добавить по ссылке")) { model.adding = AppModel.Adding(invite: "") }
                    .buttonStyle(WideButton())
                if model.inviteURL != nil {
                    ShareLink(item: model.shareText) {
                        Text(tr("Мой Love ID"))
                    }
                    .buttonStyle(WideButton(filled: false))
                }
            }
        }
        .padding(18)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct Banner: View {
    let text: String
    let action: String?
    let symbol: String
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.muted)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action, action: perform)
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(14)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
