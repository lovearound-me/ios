import SwiftUI

/// Variant А: circles, like the Mac menu. The first one is «Кому-нибудь на
/// свете», then the close people, then everyone else. A tap sends.
struct MainView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    Text(tr("О ком думаешь?"))
                        .font(.system(size: 15, weight: .semibold))
                    LazyVGrid(columns: columns, spacing: 8) {
                        AnyoneCircle(sent: model.justSent == AppModel.anyoneID) { model.sendAnyone() }
                        ForEach(model.circles) { contact in
                            PersonCircle(contact: contact, sent: model.justSent == contact.id) {
                                model.send(contact)
                            }
                        }
                    }
                    if model.loaded && model.contacts.isEmpty {
                        EmptyHint()
                    }
                }
                .padding(.horizontal, 2)
            }
            // What just happened, over the bottom edge: seen wherever the list is scrolled.
            .overlay(alignment: .bottom) {
                if let caption = model.caption {
                    Text(caption)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.caption)
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(tr("Настройки"))
                }
            }
        }
        .task { await model.refresh() }
    }
}

private let circleSize: CGFloat = 50

struct PersonCircle: View {
    let contact: Contact
    let sent: Bool
    let action: () -> Void

    private var color: Color { Palette.color(contact.color) }

    private var initial: String {
        String(contact.label.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(sent ? color : color.opacity(0.18))
                Circle().strokeBorder(color, lineWidth: 3)
                Text(sent ? "♥" : initial)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: circleSize, height: circleSize)
            .animation(.easeOut(duration: 0.2), value: sent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(contact.label)
    }
}

struct AnyoneCircle: View {
    let sent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(sent ? Palette.star : Palette.star.opacity(0.18))
                Circle().strokeBorder(Palette.star, lineWidth: 3)
                Image(systemName: sent ? "heart.fill" : "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(sent ? .white : Palette.star)
            }
            .frame(width: circleSize, height: circleSize)
            .animation(.easeOut(duration: 0.2), value: sent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Кому-нибудь на свете"))
    }
}

/// No people yet: they are added in the web app, by Love ID links.
struct EmptyHint: View {
    var body: some View {
        VStack(spacing: 2) {
            Text(tr("Пока никого нет"))
                .font(.system(size: 14, weight: .semibold))
            Text(tr("Добавь людей на {site}", ["site": Config.webApp]))
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }
}
