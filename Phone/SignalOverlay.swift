import SwiftUI

/// An incoming signal: the screen edges glow in my color, eight hearts float
/// up, and in the middle a heart says someone is thinking of you. Never who.
/// A tap closes it; it fades by itself after a few seconds.
struct SignalOverlay: View {
    let color: Color
    /// Picks the emoji; new for every signal.
    let seed: Int

    @State private var bright = false

    /// Hearts only, as in the notification (Notify/Emoji.swift).
    static let warm = Emoji.pink

    /// Eight: a few hearts that each get seen, not a crowd.
    static let count = 8

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.paper
                // The glow: a wide soft band and a thin bright edge.
                Rectangle()
                    .strokeBorder(color, lineWidth: 44)
                    .blur(radius: 30)
                    .opacity(bright ? 0.75 : 0.3)
                Rectangle()
                    .strokeBorder(color, lineWidth: 8)
                    .blur(radius: 6)
                    .opacity(bright ? 0.9 : 0.4)
                ForEach(0..<Self.count, id: \.self) { i in
                    FloatingEmoji(char: Self.warm[(seed + i * 7) % Self.warm.count],
                                  x: geo.size.width * (0.1 + 0.8 * fraction(i)),
                                  size: 24 + CGFloat((i * 5) % 12),
                                  delay: Double(i) * 0.3,
                                  height: geo.size.height)
                }
                VStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.app(110))
                        .foregroundStyle(color)
                        .symbolEffect(.bounce, value: bright)
                    Text(tr("Кто-то думает о тебе"))
                        .font(.app(28, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Text(tr("только что"))
                        .font(.app(15))
                        .foregroundStyle(Theme.muted)
                }
                // The emoji pass behind the heart and the words, not over them.
                .background {
                    RadialGradient(colors: [Theme.paper, Theme.paper.opacity(0.92), Theme.paper.opacity(0)],
                                   center: .center, startRadius: 0, endRadius: 210)
                        .frame(width: 420, height: 420)
                }
                VStack {
                    Spacer()
                    Text(tr("Нажми, чтобы закрыть"))
                        .font(.app(13))
                        .foregroundStyle(Theme.faint)
                        .padding(.bottom, 64)
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatCount(5, autoreverses: true)) {
                bright = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Кто-то думает о тебе"))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("incomingSignal")
    }

    /// Spreads the emoji across the width without clumping: golden-ratio steps.
    private func fraction(_ i: Int) -> CGFloat {
        let v = Double(i) * 0.618_034 + Double(seed % 100) / 100
        return CGFloat(v - v.rounded(.down))
    }
}

struct FloatingEmoji: View {
    let char: String
    let x: CGFloat
    let size: CGFloat
    let delay: Double
    let height: CGFloat
    var duration = 3.8

    @State private var up = false

    var body: some View {
        Text(char)
            .font(.system(size: size))
            .position(x: x, y: up ? -size : height + size)
            .opacity(up ? 0.2 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: duration).delay(delay)) { up = true }
            }
    }
}
