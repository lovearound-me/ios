import SwiftUI

/// A signal just went: the edges of the whole app glow in the person's color
/// and emoji float up, as on the Mac (mac/Sources/Needed/Overlay.swift: the
/// sender sees the glow too). Nothing to tap: the circles stay usable under it.
struct SendGlow: View {
    let out: AppModel.Outgoing

    /// How long it lasts, in nanoseconds: the glow fades and the last emoji is gone.
    static let seconds: UInt64 = 4_200_000_000

    static let stars = ["⭐️", "🌟", "✨", "💫"]
    static let count = 12

    @State private var lit = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // A wide soft band and a thin bright edge, like an incoming signal.
                Rectangle()
                    .strokeBorder(out.color, lineWidth: 40)
                    .blur(radius: 28)
                    .opacity(lit ? 0 : 0.8)
                Rectangle()
                    .strokeBorder(out.color, lineWidth: 7)
                    .blur(radius: 5)
                    .opacity(lit ? 0 : 0.95)
                ForEach(0..<Self.count, id: \.self) { i in
                    FloatingEmoji(char: emoji(i),
                                  x: geo.size.width * (0.08 + 0.84 * fraction(i)),
                                  size: 24 + CGFloat((i * 5) % 12),
                                  delay: Double(i) * 0.12,
                                  height: geo.size.height,
                                  duration: 2.6)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeIn(duration: 2.6).delay(0.5)) { lit = true }
        }
        // VoiceOver hears it as an announcement; the tests find it by this.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(out.text)
        .accessibilityIdentifier("sentGlow")
    }

    private func emoji(_ i: Int) -> String {
        let set = out.stars ? Self.stars : SignalOverlay.warm
        return set[(out.seed + i * 7) % set.count]
    }

    /// Spread across the width without clumping: golden-ratio steps.
    private func fraction(_ i: Int) -> CGFloat {
        let v = Double(i) * 0.618_034 + Double(out.seed % 100) / 100
        return CGFloat(v - v.rounded(.down))
    }
}
