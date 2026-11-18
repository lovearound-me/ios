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
        let myColor = app.openSettings(showing: "myColor")
        myColor.tap()
        let blue = app.buttons["Голубой"].firstMatch
        XCTAssertTrue(blue.waitForExistence(timeout: 10))
        blue.tap()
        XCTAssertTrue(myColor.waitForExistence(timeout: 10))
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

    /// Opens Settings and returns its button `id` once it's there.
    /// CI's watch simulator is slow, and XCUITest gives the app only so long
    /// to describe its screen: asked while the app still starts or the page
    /// still slides in, it runs out, and a tap then is lost. So: wait for the
    /// gear, let the slide finish, ask for buttons only, and tap again if the
    /// page didn't come.
    func openSettings(showing id: String) -> XCUIElement {
        // The toolbar item and its button both carry the identifier.
        let gear = buttons["settings"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 20), "no settings button")
        let target = buttons[id].firstMatch
        for _ in 0..<3 {
            if gear.exists { gear.tap() }
            Thread.sleep(forTimeInterval: 1.5)
            if target.waitForExistence(timeout: 10) { return target }
        }
        XCTFail("Settings didn't open")
        return target
    }

    func signOut() {
        let signOut = openSettings(showing: "signOut")
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
