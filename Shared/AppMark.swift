import SwiftUI

/// The app's mark: a heart on the coral-to-pink circle of the icon.
struct AppMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0xF07A62), Color(hex: 0xE86A9A)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.48))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
