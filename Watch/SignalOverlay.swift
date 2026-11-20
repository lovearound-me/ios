import SwiftUI
import UserNotifications
import WatchKit

/// An incoming signal: the screen edges glow in my color, emoji float up,
/// and in the middle a heart says someone is thinking of you. Never who.
struct SignalOverlay: View {
    let color: Color
    /// Picks the emoji; new for every signal.
    let seed: Int

    @State private var bright = false

    /// Hearts only, as in the iPhone's notification (Notify/Emoji.swift).
    static let warm = ["💖", "💕", "💗", "💞", "💓", "💘", "🩷", "❤️", "💝"]

    /// Eight: a few hearts that each get seen, not a crowd.
    static let count = 8

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(color, lineWidth: 12)
                    .blur(radius: 9)
                    .opacity(bright ? 1 : 0.4)
                ForEach(0..<Self.count, id: \.self) { i in
                    FloatingEmoji(char: Self.warm[(seed + i * 7) % Self.warm.count],
                                  x: geo.size.width * (0.12 + 0.76 * fraction(i)),
                                  size: 15 + CGFloat((i * 5) % 6),
                                  delay: Double(i) * 0.32,
                                  height: geo.size.height)
                }
                VStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: bright)
                    Text(tr("Кто-то думает о тебе"))
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        // Stays readable when an emoji floats behind it.
                        .shadow(color: .black, radius: 3)
                        .shadow(color: .black, radius: 3)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatCount(5, autoreverses: true)) {
                bright = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Кто-то думает о тебе"))
    }

    /// Spreads the emoji across the width without clumping: golden-ratio steps.
    private func fraction(_ i: Int) -> CGFloat {
        let v = Double(i) * 0.618_034 + Double(seed % 100) / 100
        return CGFloat(v - v.rounded(.down))
    }
}

private struct FloatingEmoji: View {
    let char: String
    let x: CGFloat
    let size: CGFloat
    let delay: Double
    let height: CGFloat

    @State private var up = false

    var body: some View {
        Text(char)
            .font(.system(size: size))
            .position(x: x, y: up ? -size : height + size)
            .opacity(up ? 0.15 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 3.4).delay(delay)) { up = true }
            }
    }
}

/// The long look of a heart's notification (category `signal`), when the
/// app isn't in front: the glow in my color, and nothing about who.
final class SignalNotificationController: WKUserNotificationHostingController<SignalNotificationView> {
    /// The hearts the notification came with: the server's wave for this
    /// watch, or the iPhone's text when the phone's notification is shown here.
    /// Observed, so the view redraws when `didReceive` fills it in.
    private let wave = SignalNotificationView.Wave()

    override var body: SignalNotificationView {
        SignalNotificationView(color: Palette.color(AppModel.savedColor), box: wave)
    }

    /// watchOS shows the dynamic view only once this has been called on it;
    /// without it, it waits, then falls back to the static look. watchOS has
    /// tapped once already (or not at all, with «Вибрация» off).
    override func didReceive(_ notification: UNNotification) {
        wave.text = SignalNotificationView.hearts(in: notification.request.content.body)
        // There's nothing to read or answer: the heart goes away by itself,
        // like the app's own, instead of waiting for «Закрыть» under it.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shownFor) { [weak self] in
            self?.performDismissAction()
        }
    }

    /// How long the long look stays, the app's own heart's time.
    static let shownFor: Double = 5.5
}

struct SignalNotificationView: View {
    final class Wave: ObservableObject {
        @Published var text: String
        init(_ text: String = "") { self.text = text }
    }

    let color: Color
    /// ✨💗💖💞💖💗✨ above the heart; empty for a bare «♥».
    @ObservedObject var box: Wave
    private var wave: String { box.text }

    @State private var bright = false

    /// The emoji of a notification's text, without the words the iPhone may
    /// add after them (the view says them itself) and without a bare «♥».
    static func hearts(in body: String) -> String {
        let text = body.replacingOccurrences(of: tr("Кто-то думает о тебе"), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text == "♥" ? "" : text
    }

    var body: some View {
        VStack(spacing: 6) {
            if !wave.isEmpty {
                Text(wave)
                    .font(.system(size: 18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 56, height: 56)
                    .blur(radius: 16)
                    .opacity(bright ? 0.9 : 0.35)
                Image(systemName: "heart.fill")
                    .font(.system(size: wave.isEmpty ? 40 : 34))
                    .foregroundStyle(color)
            }
            .frame(height: wave.isEmpty ? 84 : 70)
            Text(tr("Кто-то думает о тебе"))
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatCount(3, autoreverses: true)) {
                bright = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Кто-то думает о тебе"))
    }
}
