import Foundation

enum Config {
    /// needed-server on Cloud Run: REST, see the server's docs/schema.md.
    static let apiBase = URL(string: "https://api.lovearound.me")!
    /// Firebase Web API key: public, identifies the project to Firebase Auth.
    static let firebaseAPIKey = "AIzaSyBZJfln_KXsxRxo3fvVaV1ePmiVUIn5YXY"
    /// Where a person confirms a pairing code (the QR holds it with the code).
    static let pairingPage = "lovearound.me/login/devices"
    /// The web app, where people add others and manage devices.
    static let webApp = "app.lovearound.me"
    /// The site: invite links /i/<code>, the Google sign-in bridge /signin/, docs.
    static let site = "https://lovearound.me"
    /// Links the iPhone app opens: lovearound://add/<code>, lovearound://signin?….
    static let urlScheme = "lovearound"
    #if os(watchOS)
    private static let platform = "watch"
    #else
    private static let platform = "ios"
    #endif
    /// Sent as `X-Client` with every request, so the server logs which version sent what.
    static let client = platform + "/" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
}
