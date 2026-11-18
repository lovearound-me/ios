import XCTest

/// Taps through the iPhone app on made-up data (`--demo`, Phone/Demo.swift):
/// nothing signs in or reaches the server. In Russian, as the texts are keyed.
final class PhoneDemoUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTapOnACircleSends() {
        let app = XCUIApplication.russian(demo: "home")
        let circle = app.buttons["Аня"]
        XCTAssertTrue(circle.waitForExistence(timeout: 10))
        circle.tap()
        XCTAssertTrue(app.element("toast").waitForExistence(timeout: 3))
        XCTAssertEqual(app.element("toast").label, "Аня — улетело ♥")
    }

    func testBigHeartSendsToSomeoneOutThere() {
        let app = XCUIApplication.russian(demo: "home")
        let heart = app.element("anyone")
        XCTAssertTrue(heart.waitForExistence(timeout: 10))
        heart.tap()
        XCTAssertTrue(app.element("toast").waitForExistence(timeout: 3))
        XCTAssertEqual(app.element("toast").label, "Кому-нибудь на свете — улетело ✨")
        // Once an hour: the heart waits now.
        XCTAssertTrue(app.element("anyoneNote").label.hasPrefix("Кому-нибудь — через"))
        XCTAssertFalse(heart.isEnabled)
    }

    func testAddByLink() {
        let app = XCUIApplication.russian(demo: "home")
        app.element("addByLink").tap()
        let link = app.element("inviteLink")
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("https://lovearound.me/i/HQ7MX-4RT2P")
        app.element("newName").tap()
        app.element("newName").typeText("Катя")
        app.element("addContact").tap()
        // Six of twelve are close, so the new one gets a circle.
        XCTAssertTrue(app.buttons["Катя"].waitForExistence(timeout: 5))
    }

    func testOwnLinkIsRefused() {
        let app = XCUIApplication.russian(demo: "home")
        app.element("addByLink").tap()
        // The name first: with it empty «Добавить» is off anyway.
        let name = app.element("newName")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Я")
        XCTAssertEqual(name.value as? String, "Я")
        let link = app.element("inviteLink")
        link.tap()
        link.typeText("https://lovearound.me/i/GSSV7-A33HN")
        XCTAssertTrue(app.staticTexts["Это твоя собственная ссылка"].waitForExistence(timeout: 3))
        // iOS 26 reports a greyed-out toolbar button as enabled: tap it and
        // see that nothing happens instead.
        app.element("addContact").tap()
        XCTAssertTrue(link.waitForExistence(timeout: 2), "the sheet closed")
        XCTAssertFalse(app.buttons["Я"].exists)
    }

    func testBookMakesSomeoneClose() {
        let app = XCUIApplication.russian(demo: "home")
        XCTAssertFalse(app.buttons["Ваня"].waitForExistence(timeout: 3), "Ваня starts outside «Рядом»")
        app.openTab("Книга")
        let edit = app.element("edit-Ваня")
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let close = app.switches["Рядом"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        // A Toggle's own switch sits inside it: a tap on the row's middle may miss it.
        let knob = close.switches.firstMatch
        (knob.exists ? knob : close).tap()
        XCTAssertEqual(close.value as? String, "1")
        app.element("saveContact").tap()
        app.openTab("Сердечки")
        XCTAssertTrue(app.buttons["Ваня"].waitForExistence(timeout: 5))
    }

    func testBoardGetsAToken() {
        let app = XCUIApplication.russian(demo: "toys")
        app.openTab("Игрушки")
        let add = app.element("addBoard")
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let name = app.element("boardName")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Лампа")
        app.element("createBoard").tap()
        XCTAssertTrue(app.element("boardToken").waitForExistence(timeout: 5))
    }

    func testPairByCode() {
        let app = XCUIApplication.russian(demo: "toys")
        app.openTab("Игрушки")
        let pair = app.element("pairByCode")
        XCTAssertTrue(pair.waitForExistence(timeout: 5))
        pair.tap()
        let code = app.element("pairCode")
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        code.tap()
        code.typeText("482913")
        let confirm = app.element("confirmPairing")
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Подключено"].waitForExistence(timeout: 5))
    }

    /// The QR on a watch or a lamp opens the pairing with its digits in.
    /// The https form (lovearound.me/login/devices#…) takes the site's
    /// apple-app-site-association, so here it's the app's own scheme.
    func testPairLinkOpensPairing() {
        let app = XCUIApplication.russian(demo: "home")
        XCTAssertTrue(app.element("anyone").waitForExistence(timeout: 10))
        app.open(URL(string: "lovearound://pair/482913")!)
        let code = app.element("pairCode")
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertEqual(code.value as? String, "482913")
        XCTAssertTrue(app.element("confirmPairing").waitForExistence(timeout: 5))
    }

    func testSignOut() {
        let app = XCUIApplication.russian(demo: "settings")
        app.signOut()
        XCTAssertTrue(app.element("signInScreen").waitForExistence(timeout: 5))
    }
}

extension XCUIApplication {
    static func russian(demo: String? = nil, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (demo.map { ["--demo", $0] } ?? []) + ["-AppleLanguages", "(ru)", "-AppleLocale", "ru"]
        app.launchEnvironment = environment
        app.launch()
        return app
    }

    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func openTab(_ name: String) {
        let inBar = tabBars.buttons[name]
        if inBar.waitForExistence(timeout: 5) {
            inBar.tap()
        } else {
            buttons[name].firstMatch.tap()
        }
    }

    /// Settings → «Выйти» → the alert's «Выйти».
    func signOut() {
        openTab("Настройки")
        let signOut = element("signOut")
        for _ in 0..<6 where !signOut.isHittable {
            swipeUp()
        }
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        let confirm = alerts.buttons["Выйти"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no «Выйти на этом iPhone?» alert")
        confirm.tap()
    }
}
