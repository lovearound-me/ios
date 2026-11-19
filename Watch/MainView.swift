import SwiftUI
import WatchKit

/// The people, the way Settings → «Вид» says: honeycomb bubbles (the
/// default), circles, circles with names, or a list. The first is always
/// «Кому-нибудь на свете», then the close people, then everyone else.
/// A tap sends. A held finger shows the whole name: let go and it goes,
/// slide away and it doesn't.
struct MainView: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            people
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
                            .accessibilityIdentifier("caption")
                    }
                }
                .overlay {
                    if let target = model.peeking {
                        PeekView(target: target)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.caption)
                .animation(.easeOut(duration: 0.15), value: model.peeking)
                .navigationDestination(isPresented: $showSettings) { SettingsView() }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(tr("Настройки"))
                        .accessibilityIdentifier("settings")
                    }
                }
        }
        .task { await model.refresh() }
    }

    @ViewBuilder private var people: some View {
        switch model.layout {
        case .hive: HiveView()
        case .circles: GridView(named: false)
        case .named: GridView(named: true)
        case .list: ListView()
        }
    }
}

/// «О ком думаешь?» over the people.
private struct Heading: View {
    var body: some View {
        Text(tr("О ком думаешь?"))
            .font(.system(size: 15, weight: .semibold))
            .accessibilityIdentifier("mainHeading")
    }
}

/// Under the people: why there are none.
private struct Footer: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.sendingOff {
            Text(tr("Отправка с часов выключена"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("sendingOff")
        } else if model.loaded && model.contacts.isEmpty {
            EmptyHint()
        }
    }
}

// MARK: Tap and hold

/// A tap sends at once. Held for a moment, the whole name shows over the
/// screen (PeekView); letting go sends, sliding the finger away doesn't.
private struct Sends: ViewModifier {
    let target: Target
    @EnvironmentObject var model: AppModel

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { model.send(target) }
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        switch value {
                        case .first:
                            model.pressStarted()
                        case .second(true, let drag):
                            let moved = drag.map { hypot($0.translation.width, $0.translation.height) } ?? 0
                            model.holding(target, moved: moved)
                        default:
                            break
                        }
                    }
                    .onEnded { _ in model.released(target) }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(target.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.send(target) }
    }
}

private extension View {
    func sends(_ target: Target) -> some View { modifier(Sends(target: target)) }
}

/// The held one: big, with the whole name.
struct PeekView: View {
    let target: Target
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 6) {
                Mark(target: target, size: 74, sent: false, style: .ring)
                Text(target.label)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                Text(tr("Отпусти, и улетит. Смахни, чтобы отменить."))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
        }
        // If the finger's own gesture was lost (the list scrolled away under
        // it): a tap here sends, a swipe cancels.
        .contentShape(Rectangle())
        .onTapGesture { model.sendPeeked() }
        .gesture(DragGesture(minimumDistance: 15).onEnded { _ in model.cancelPeek() })
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("peek")
    }
}

// MARK: The marks

/// A person's circle or bubble: the first letter in their color, a heart
/// for a moment once sent. «Кому-нибудь на свете» has sparkles in gold.
struct Mark: View {
    enum Style {
        /// A ring in the color around a dark fill (circles, the held one).
        case ring
        /// Filled with the color, like an app's icon (bubbles, list).
        case filled
    }

    let target: Target
    let size: CGFloat
    let sent: Bool
    let style: Style

    var body: some View {
        let color = target.color
        ZStack {
            switch style {
            case .ring:
                Circle().fill(sent ? color : color.opacity(0.18))
                Circle().strokeBorder(color, lineWidth: max(2, size * 0.06))
            case .filled:
                Circle().fill(color.gradient)
                if sent {
                    Circle().strokeBorder(Color.white, lineWidth: max(2, size * 0.06))
                }
            }
            symbol(color)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.2), value: sent)
    }

    @ViewBuilder private func symbol(_ color: Color) -> some View {
        if sent {
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Color.white)
        } else if case .anyone = target {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(style == .filled ? Color.white : color)
        } else {
            Text(target.initial)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }
}

// MARK: Соты

/// Bubbles in rows of three and four, offset like a honeycomb; the ones
/// towards the screen's edges shrink, as on the watch's own app screen.
private struct HiveView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let screen = geo.size
            let size = (screen.width / 4.5).rounded(.down)
            let rows = hiveRows(model.targets)
            ScrollView {
                VStack(spacing: -size * 0.05) {
                    Heading().padding(.bottom, size * 0.15)
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: size * 0.1) {
                            ForEach(rows[r]) { target in
                                Mark(target: target, size: size, sent: model.justSent == target.id, style: .filled)
                                    .sends(target)
                                    .visualEffect { content, proxy in
                                        content.scaleEffect(hiveScale(proxy.frame(in: .scrollView), in: screen))
                                    }
                            }
                        }
                    }
                    Footer().padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                // Room for the last rows to come to the middle, where they're biggest.
                .padding(.bottom, screen.height * 0.3)
            }
        }
    }
}

/// 3, 4, 3, 4…, the star in the middle of the first row.
func hiveRows(_ targets: [Target]) -> [[Target]] {
    var rows: [[Target]] = []
    var rest = targets[...]
    while !rest.isEmpty {
        let n = rows.count % 2 == 0 ? 3 : 4
        rows.append(Array(rest.prefix(n)))
        rest = rest.dropFirst(n)
    }
    if let first = rows.first, first.count >= 2 { rows[0].swapAt(0, 1) }
    return rows
}

/// Full size near the middle of the screen, down to under half at the corners.
func hiveScale(_ frame: CGRect, in screen: CGSize) -> CGFloat {
    let dx = frame.midX - screen.width / 2
    let dy = (frame.midY - screen.height / 2) * 0.85
    let far = (dx * dx + dy * dy).squareRoot() - screen.width * 0.3
    return min(1, max(0.45, 1 - far / (screen.width * 0.55)))
}

// MARK: Кружочки

private struct GridView: View {
    /// The name under each circle.
    let named: Bool
    @EnvironmentObject var model: AppModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Heading()
                LazyVGrid(columns: columns, spacing: named ? 6 : 8) {
                    ForEach(model.targets) { target in
                        VStack(spacing: 2) {
                            Mark(target: target, size: named ? 44 : 50, sent: model.justSent == target.id, style: .ring)
                            if named {
                                Text(target.short)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .sends(target)
                    }
                }
                Footer()
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: Список

private struct ListView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                Heading().padding(.bottom, 3)
                ForEach(model.targets) { target in
                    row(target, sent: model.justSent == target.id)
                }
                Footer().padding(.top, 4)
            }
        }
    }

    private func row(_ target: Target, sent: Bool) -> some View {
        HStack(spacing: 9) {
            Mark(target: target, size: 28, sent: false, style: .filled)
            Text(target.label)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if sent {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Palette.link)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(sent ? target.color.opacity(0.4) : Color(white: 0.14),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: sent)
        .sends(target)
    }
}

/// No people yet: they are added in the iPhone app, by Love ID links.
struct EmptyHint: View {
    var body: some View {
        VStack(spacing: 2) {
            Text(tr("Пока никого нет"))
                .font(.system(size: 14, weight: .semibold))
            Text(tr("Добавь людей в Love Around на iPhone"))
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }
}
