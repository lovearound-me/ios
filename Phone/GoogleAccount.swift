import GoogleSignIn
import UIKit

/// «Войти через Google» with Google's own sign-in: Google shows its account
/// chooser over the app and gives back an ID token, which Auth trades for a
/// Firebase session. The client id is the iPhone app's in Firebase
/// (`GIDClientID` in Info.plist); its reversed form is a URL scheme, for
/// Google's answer.
@MainActor
enum GoogleAccount {
    enum Failure: Error {
        /// Closed by the person: nothing to say.
        case cancelled
        case failed
    }

    static func idToken() async throws -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else {
            throw Failure.failed
        }
        while let next = top.presentedViewController { top = next }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: top)
            guard let token = result.user.idToken?.tokenString else { throw Failure.failed }
            // The app keeps Firebase's session only, not Google's.
            GIDSignIn.sharedInstance.signOut()
            return token
        } catch let error as NSError where error.domain == kGIDSignInErrorDomain && error.code == GIDSignInError.canceled.rawValue {
            throw Failure.cancelled
        }
    }

    /// Google's answer, when it comes back as a link.
    static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }
}
