import XCTest

/// Taps through the app on made-up data (`--demo`): nothing reaches the
/// server. Runs in GitHub Actions on every push.
final class DemoUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTapOnACircleSends() {
        let app = XCUIApplication.russian(demo: "circles")
        XCTAssertTrue(app.element("mainHeading").waitForExistence(timeout: 15))
        app.buttons["Аня"].tap()
        let caption = app.element("caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 3))
        XCTAssertEqual(caption.label, "Аня — улетело ♥")
    }

    func testStarSendsToSomeoneOutThere() {
        let app = XCUIApplication.russian(demo: "circles")
        app.buttons["Кому-нибудь на свете"].tap()
        let caption = app.element("caption")
        XCTAssertTrue(caption.waitForExistence(timeout: 3))
        XCTAssertEqual(caption.label, "Кому-нибудь на свете — улетело ✨")
    }

    func testCodeScreenAndComputer() {
        let app = XCUIApplication.russian(demo: "code")
        let code = app.element("pairingCode")
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        XCTAssertEqual(code.label, "482 913")
        app.buttons["Ввести на компьютере"].tap()
        XCTAssertTrue(app.staticTexts["и введи код"].waitForExistence(timeout: 5))
    }

    func testMyColor() {
        let app = XCUIApplication.russian(demo: "circles")
        app.element("settings").tap()
        let myColor = app.element("myColor")
        XCTAssertTrue(myColor.waitForExistence(timeout: 5))
        myColor.tap()
        app.buttons["Голубой"].tap()
        XCTAssertTrue(myColor.waitForExistence(timeout: 5))
    }

    func testSignOut() {
        let app = XCUIApplication.russian(demo: "circles")
        app.signOut()
        XCTAssertTrue(app.element("codeSignIn").waitForExistence(timeout: 5))
    }
}

extension XCUIApplication {
    /// The app in Russian, the language the texts are keyed by.
    static func russian(demo: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (demo.map { ["--demo", $0] } ?? []) + ["-AppleLanguages", "(ru)", "-AppleLocale", "ru"]
        app.launch()
        return app
    }

    /// An element by its accessibilityIdentifier, whatever kind it is.
    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func signOut() {
        buttons["settings"].tap()
        // CI's watch simulator is slow, and XCUITest gives the app only so
        // long to describe its screen: asked for every element while the
        // settings page still slides in, it once ran out. So: let the slide
        // finish, then ask for buttons only.
        Thread.sleep(forTimeInterval: 1.5)
        let signOut = buttons["signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        // The settings page slides in: a tap during the slide is lost, so wait
        // until the button takes taps, and tap again if no alert came.
        // watchOS drops identifiers on alert buttons, and the settings list
        // with its own «Выйти» stays in the tree behind the alert.
        let confirm = descendants(matching: .button)
            .matching(NSPredicate(format: "label == %@ AND identifier != %@", "Выйти", "signOut")).firstMatch
        for _ in 0..<3 where !confirm.exists {
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"),
                                                               object: signOut)], timeout: 5)
            signOut.tap()
            _ = confirm.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(confirm.exists, "no «Выйти?» alert")
        confirm.tap()
    }
}
