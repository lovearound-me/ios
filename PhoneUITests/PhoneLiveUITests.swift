import XCTest

/// The real thing, against the production server: the test account's book
/// and devices load, one heart goes to its person, sign out. Skipped unless
/// both are given:
///
///     TEST_RUNNER_LOVEAROUND_LIVE=<name> TEST_RUNNER_LOVEAROUND_ID_TOKEN=<token> \
///       xcodebuild test … -only-testing:LoveAroundUITests/PhoneLiveUITests
///
/// The token is a Firebase ID token of the test account, an hour long, from
/// tools/test-id-token.py on the server: the app takes it at launch (DEBUG
/// builds only) and keeps nothing, so no password or refresh token comes here.
final class PhoneLiveUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSendAndSignOut() throws {
        let env = ProcessInfo.processInfo.environment
        guard let person = env["LOVEAROUND_LIVE"], !person.isEmpty,
              let token = env["LOVEAROUND_ID_TOKEN"], !token.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_LOVEAROUND_LIVE and TEST_RUNNER_LOVEAROUND_ID_TOKEN")
        }
        let app = XCUIApplication.russian(environment: ["LOVEAROUND_TEST_ID_TOKEN": token])

        let circle = app.buttons[person]
        XCTAssertTrue(circle.waitForExistence(timeout: 30), "no circle for \(person): the book didn't load")
        shot(app)
        circle.tap()
        XCTAssertTrue(app.element("sentGlow").waitForExistence(timeout: 3))
        shot(app)
        // The glow comes at once; if the server says no, a red toast
        // follows. Watch for one a while.
        XCTAssertFalse(app.element("toast").waitForExistence(timeout: 4), "the server didn't take the heart")

        app.openTab("Книга")
        XCTAssertTrue(app.element("send-\(person)").waitForExistence(timeout: 5))
        shot(app)

        app.openTab("Устройства")
        // The test account has one device of its own (the tools' «claude»).
        // A row reads as one: «claude, Принимает и отправляет · …».
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "claude")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the devices didn't load")
        shot(app)

        app.openTab("Настройки")
        XCTAssertTrue(app.element("settingsAccount").waitForExistence(timeout: 5))
        shot(app)

        app.signOut()
        XCTAssertTrue(app.element("signInScreen").waitForExistence(timeout: 5))
    }

    /// Kept on success too: rerunning to see the screens sends another heart.
    private func shot(_ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
