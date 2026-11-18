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
        element("settings").tap()
        let signOut = element("signOut")
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        let confirm = element("signOutConfirm")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }
}
