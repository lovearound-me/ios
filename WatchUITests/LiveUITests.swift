import XCTest

/// The real thing, against the production server: sign in by code, send one
/// heart, sign out. Skipped unless the person to send to is given:
///
///     TEST_RUNNER_LOVEAROUND_LIVE=<name> xcodebuild test … -only-testing:LoveAroundWatchUITests/LiveUITests
///
/// The test prints «LOVEAROUND PAIRING CODE: 482913» and waits up to nine
/// minutes for someone to confirm it, as the test account
/// (tools/confirm-pairing.py on the server). That account's only person is
/// the one the heart goes to.
final class LiveUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testPairSendSignOut() throws {
        guard let person = ProcessInfo.processInfo.environment["LOVEAROUND_LIVE"], !person.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_LOVEAROUND_LIVE to the name of the test account's person")
        }
        let app = XCUIApplication.russian()

        // A session left from an earlier run: start signed out.
        if app.element("mainHeading").waitForExistence(timeout: 5) {
            app.signOut()
        }
        let codeSignIn = app.element("codeSignIn")
        XCTAssertTrue(codeSignIn.waitForExistence(timeout: 10))
        codeSignIn.tap()

        let code = app.element("pairingCode")
        XCTAssertTrue(code.waitForExistence(timeout: 30), "no code from the server")
        let digits = code.label.replacingOccurrences(of: " ", with: "")
        print("LOVEAROUND PAIRING CODE: \(digits)")
        NSLog("LOVEAROUND PAIRING CODE: %@", digits)
        add(XCTAttachment(screenshot: app.screenshot()))

        XCTAssertTrue(app.element("mainHeading").waitForExistence(timeout: 540), "nobody confirmed the code")
        add(XCTAttachment(screenshot: app.screenshot()))

        let circle = app.buttons[person]
        XCTAssertTrue(circle.waitForExistence(timeout: 20), "no circle for \(person)")
        circle.tap()
        let caption = app.element("caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 3))
        // «Улетело» shows at once; a failure replaces it when the server answers.
        Thread.sleep(forTimeInterval: 1.5)
        add(XCTAttachment(screenshot: app.screenshot()))
        XCTAssertEqual(caption.label, "\(person) — улетело ♥")

        app.signOut()
        XCTAssertTrue(app.element("codeSignIn").waitForExistence(timeout: 5))
    }
}
