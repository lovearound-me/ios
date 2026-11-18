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
        add(XCTAttachment(screenshot: app.screenshot()))
        circle.tap()
        let toast = app.element("toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        // «Улетело» shows at once; a failure replaces it when the server answers.
        Thread.sleep(forTimeInterval: 1.5)
        add(XCTAttachment(screenshot: app.screenshot()))
        XCTAssertEqual(toast.label, "\(person) — улетело ♥")

        app.openTab("Книга")
        XCTAssertTrue(app.element("send-\(person)").waitForExistence(timeout: 5))
        add(XCTAttachment(screenshot: app.screenshot()))

        app.openTab("Игрушки")
        // The test account has one device of its own (the tools' «claude»).
        // A row reads as one: «claude, Принимает и отправляет · …».
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "claude")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the devices didn't load")
        add(XCTAttachment(screenshot: app.screenshot()))

        app.openTab("Настройки")
        XCTAssertTrue(app.element("account").waitForExistence(timeout: 5))
        add(XCTAttachment(screenshot: app.screenshot()))

        app.signOut()
        XCTAssertTrue(app.element("signInScreen").waitForExistence(timeout: 5))
    }
}
