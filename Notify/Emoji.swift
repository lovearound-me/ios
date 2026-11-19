/// The emoji of an incoming heart, on screen and in its notification: hearts
/// only. A mix with cats, coffee and 👍 read as noise, not as someone's love.
enum Emoji {
    /// Pinks and reds: the wave's hearts, and what floats up on screen.
    static let pink = ["💖", "💕", "💗", "💞", "💓", "💘", "🩷", "❤️", "💝"]

    /// «Одно сердечко»: one of these, new each time.
    static let hearts = ["❤️", "🧡", "💛", "💚", "💙", "💜", "💖", "💕", "💗"]

    /// «Волна сердечек»: three hearts rising to the middle and back, sparkles
    /// at the ends, so it reads as one gesture: ✨💗💖💞💖💗✨. New each time.
    static func wave() -> String {
        let h = pink.shuffled()
        return "✨" + h[0] + h[1] + h[2] + h[1] + h[0] + "✨"
    }

    /// «Три сердечка»: the wave's middle, 💕💖💕.
    static func three() -> String {
        let h = pink.shuffled()
        return h[0] + h[1] + h[0]
    }
}
