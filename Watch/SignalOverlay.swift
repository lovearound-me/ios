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

    /// The Mac's mix: hearts among hugs, cats, flowers and treats, so it reads
    /// as warmth from anyone close, not only love.
    static let warm = [
        "❤️", "🧡", "💛", "💚", "💙", "💜", "💖", "💕", "💗",
        "🫂", "🤗", "🫶", "🥰", "😊", "☺️",
        "😺", "😸", "😻", "😽", "🐈", "🐱",
        "🐶", "🐻", "🐼", "🦔", "🐰", "🦊", "🐥", "🧸",
        "💪", "🙌", "👍", "✊", "👏",
        "☀️", "🌻", "🌷", "🌸", "🌼", "🌈", "🍀", "✨", "⭐️",
        "☕️", "🍵", "🍪", "🍰", "🍓", "🎈",
    ]

    /// Twelve: enough to feel like a shower, few enough to stay smooth.
    static let count = 12

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
    override var body: SignalNotificationView {
        SignalNotificationView(color: Palette.color(AppModel.savedColor))
    }
}

struct SignalNotificationView: View {
    let color: Color

    @State private var bright = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 64, height: 64)
                    .blur(radius: 18)
                    .opacity(bright ? 0.9 : 0.35)
                Image(systemName: "heart.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(color)
            }
            .frame(height: 84)
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
