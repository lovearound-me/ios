import SwiftUI

/// Variant Б of the mockups, as changed after the first try on a phone
/// (2026-11-19): «Кому-нибудь на свете» is a circle like the others, first
/// in «Рядом», and «＋» ends the circles while there is room for more.
struct HomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                banners
                circles
                if model.showsStart {
                    StartCard()
                        .transition(.opacity)
                }
                if !model.contacts.isEmpty {
                    Button { model.tab = .book } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "book.closed")
                                .foregroundStyle(Theme.muted)
                            Text(tr("Вся книга · {n}", ["n": String(model.contacts.count)]))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.app(14, weight: .semibold))
                                .foregroundStyle(Theme.faint)
                        }
                        .font(.app(16))
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
            .animation(.easeInOut(duration: 0.3), value: model.showsStart)
        }
        .background(Theme.paper.ignoresSafeArea())
        .refreshable { await model.reload() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .foregroundStyle(Theme.heart)
            Text("Love Around")
                .fontWeight(.bold)
                .foregroundStyle(Theme.ink)
        }
        .font(.app(17))
        .frame(height: 40)
    }

    @ViewBuilder private var banners: some View {
        if !model.receiveHere {
            Banner(text: tr("Этот iPhone не получает сердечки."),
                   action: tr("Включить"), symbol: "heart.slash") { model.receiveHere = true }
        } else if model.isPaused {
            Banner(text: tr("{pause}. Сигналы не придут.", ["pause": model.pauseText]),
                   action: tr("Снять паузу"), symbol: "moon.fill") { model.resume() }
        }
        if model.offline {
            Banner(text: tr("Нет связи с сервером, сигналы сейчас не приходят. Переподключаемся…"),
                   action: nil, symbol: "wifi.slash") {}
        }
    }

    private var circles: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.closeContacts.isEmpty && !model.contacts.isEmpty ? tr("Книга") : tr("Рядом"))
                .font(.app(13, weight: .semibold))
                .foregroundStyle(Theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3), spacing: 18) {
                AnyoneCircle()
                ForEach(model.homeCircles) { contact in
                    Button { model.send(contact) } label: {
                        PersonCircle(contact: contact, sent: model.justSent == contact.id)
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(contact.label)
                    .accessibilityHint(tr("Отправить сердечко"))
                }
                if !model.closeFull {
                    Button(action: model.addToClose) {
                        AddCircle()
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(tr("Добавить в «Рядом»"))
                    .accessibilityIdentifier("addToClose")
                }
            }
            Text(tr("Кому-нибудь: сердечко случайному человеку, раз в час. Он не узнает, от кого."))
                .font(.app(13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// «Кому-нибудь на свете»: a signal to one random person, once an hour. A
/// star among the people; dimmed, with the minutes left, while it waits.
struct AnyoneCircle: View {
    @EnvironmentObject var model: AppModel
    var size: CGFloat = 76

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let wait = model.anyoneWait(at: context.date)
            let sent = model.justSent == AppModel.anyoneID
            Button(action: model.sendToAnyone) {
                VStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(sent ? Theme.star : Theme.star.opacity(0.18))
                        Circle()
                            .strokeBorder(Theme.star, lineWidth: 3)
                        Image(systemName: "sparkles")
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(sent ? Color.white : Theme.star)
                            .symbolEffect(.bounce, value: sent)
                    }
                    .frame(width: size, height: size)
                    .opacity(wait != nil && !sent ? 0.5 : 1)
                    .animation(.spring(duration: 0.3), value: sent)
                    VStack(spacing: 1) {
                        Text(tr("Кому-нибудь"))
                            .font(.app(14))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        // The line is always there, empty while the star is
                        // ready: a cell that grows after a send leaves the
                        // grid's last row over the hint below it.
                        Text(wait.map { tr("через {n} мин", ["n": String($0)]) } ?? " ")
                            .font(.app(12))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .buttonStyle(PressScale())
            .disabled(wait != nil)
            // On the button itself: a new element in its place would read as
            // enabled while it waits.
            .accessibilityLabel(tr("Кому-нибудь на свете"))
            .accessibilityValue(wait.map { tr("через {n} мин", ["n": String($0)]) } ?? "")
            .accessibilityIdentifier("anyone")
        }
    }
}

/// «＋» after the circles: opens who of the book goes into «Рядом».
struct AddCircle: View {
    var size: CGFloat = 76

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .strokeBorder(Theme.faint.opacity(0.75), style: StrokeStyle(lineWidth: 2.5, dash: [6, 5]))
                Image(systemName: "plus")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(width: size, height: size)
            Text(tr("Добавить"))
                .font(.app(14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
        }
    }
}

/// «＋» among the circles: who of the book goes into «Рядом», or someone new.
struct ChooseCloseView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    model.addByLinkNext = true
                    dismiss()
                } label: {
                    Label(tr("Новый человек по ссылке"), systemImage: "link")
                        .font(.app(17, weight: .semibold))
                }
                .accessibilityIdentifier("closeNewByLink")
            }
            .listRowBackground(Theme.field)
            if !model.otherContacts.isEmpty {
                Section {
                    ForEach(model.otherContacts) { contact in
                        HStack(spacing: 14) {
                            PersonCircle(contact: contact, size: 36, named: false)
                            Text(contact.label)
                                .font(.app(17))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button { model.setClose(contact, true) } label: {
                                Image(systemName: "plus")
                                    .font(.app(15, weight: .bold))
                                    .foregroundStyle(Theme.link)
                                    .frame(width: 34, height: 34)
                                    .background(Theme.heartSoft, in: Circle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.closeFull)
                            .accessibilityLabel(tr("Добавить в «Рядом»: {name}", ["name": contact.label]))
                            .accessibilityIdentifier("makeClose-\(contact.label)")
                        }
                    }
                } header: {
                    Text(tr("Из книги"))
                } footer: {
                    Text(model.closeFull
                         ? tr("Рядом уже 12 человек: сначала убери кого-нибудь.")
                         : tr("В «Рядом» {n} из 12.", ["n": String(model.closeContacts.count)]))
                }
                .listRowBackground(Theme.field)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle(tr("Добавить в «Рядом»"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Готово")) { dismiss() }
                    .accessibilityIdentifier("closeDone")
            }
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
                    .font(.app(14))
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
                .font(.app(16))
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
                .font(.app(14))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action, action: perform)
                    .font(.app(14, weight: .semibold))
            }
        }
        .padding(14)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
