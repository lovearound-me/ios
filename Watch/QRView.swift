import QRCodeGenerator
import SwiftUI

/// A QR code drawn module by module: watchOS has no Core Image filter for it.
struct QRView: View {
    let text: String

    var body: some View {
        if let qr = try? QRCode.encode(text: text, ecl: .medium) {
            Canvas { context, size in
                let cell = size.width / CGFloat(qr.size)
                for y in 0..<qr.size {
                    for x in 0..<qr.size where qr.getModule(x: x, y: y) {
                        // A hair wider than the cell, so no seams show between modules.
                        let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                          width: cell + 0.4, height: cell + 0.4)
                        context.fill(Path(rect), with: .color(.black))
                    }
                }
            }
            // Two modules of white around it: enough quiet zone for a phone camera.
            .padding(7)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
