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
        // No line saying so: the app's edges glow in her color, emoji fly.
        let glow = app.element("sentGlow")
        XCTAssertTrue(glow.waitForExistence(timeout: 3))
        XCTAssertEqual(glow.label, "Аня — улетело ♥")
        XCTAssertFalse(app.element("toast").exists)
    }

    func testStarSendsToSomeoneOutThere() {
        let app = XCUIApplication.russian(demo: "home")
        let star = app.element("anyone")
        XCTAssertTrue(star.waitForExistence(timeout: 10))
        star.tap()
        let glow = app.element("sentGlow")
        XCTAssertTrue(glow.waitForExistence(timeout: 3))
        XCTAssertEqual(glow.label, "Кому-нибудь на свете — улетело ✨")
        // Once an hour: the star waits now, with the minutes under it.
        XCTAssertTrue((star.value as? String)?.hasPrefix("через") == true, "\(String(describing: star.value))")
        XCTAssertFalse(star.isEnabled)
    }

    /// «＋» after the circles → «Новый человек по ссылке» → the add sheet.
    func testAddByLink() {
        let app = XCUIApplication.russian(demo: "home")
        let plus = app.element("addToClose")
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        let byLink = app.element("closeNewByLink")
        XCTAssertTrue(byLink.waitForExistence(timeout: 5))
        byLink.tap()
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
        let app = XCUIApplication.russian(demo: "book")
        let add = app.element("bookAdd")
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
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

    /// «＋» after the circles → a «+» by someone from the book → their circle.
    func testPlusCircleMakesSomeoneClose() {
        let app = XCUIApplication.russian(demo: "home")
        XCTAssertFalse(app.buttons["Дима"].waitForExistence(timeout: 3), "Дима starts outside «Рядом»")
        app.element("addToClose").tap()
        let make = app.element("makeClose-Дима")
        XCTAssertTrue(make.waitForExistence(timeout: 5))
        make.tap()
        // Now in «Рядом», so no longer offered.
        XCTAssertTrue(make.waitForNonExistence(timeout: 5))
        app.element("closeDone").tap()
        XCTAssertTrue(app.buttons["Дима"].waitForExistence(timeout: 5))
    }

    /// Settings → «Что делает»: off, and the home screen says so, with a way
    /// back on.
    func testReceiveHereOff() {
        let app = XCUIApplication.russian(demo: "settings")
        let does = app.element("settingsDoes")
        XCTAssertTrue(does.waitForExistence(timeout: 10))
        does.tap()
        let receive = app.switches["receiveHere"]
        XCTAssertTrue(receive.waitForExistence(timeout: 5))
        XCTAssertEqual(receive.value as? String, "1")
        let knob = receive.switches.firstMatch
        (knob.exists ? knob : receive).tap()
        XCTAssertEqual(receive.value as? String, "0")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.element("settingsWho").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("settingsWho").label.contains("Не принимает сердечки"), app.element("settingsWho").label)
        XCTAssertFalse(app.element("pause").isEnabled)
        app.openTab("Сердечки")
        let banner = app.staticTexts["Этот iPhone не получает сердечки."]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        app.buttons["Включить"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
    }

    /// Settings → «Уведомление»: the pick is checked, and the row says it.
    func testNotifyLookPicks() {
        let app = XCUIApplication.russian(demo: "settings")
        let row = app.element("settingsLook")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Много эмодзи"), row.label)
        row.tap()
        let three = app.element("look-three")
        XCTAssertTrue(three.waitForExistence(timeout: 5))
        XCTAssertFalse(three.isSelected)
        three.tap()
        XCTAssertTrue(three.isSelected)
        XCTAssertFalse(app.element("look-many").isSelected)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Три эмодзи"), row.label)
    }

    /// Settings → «Кто может достучаться» → «Тихие часы»: the times show,
    /// and the row says when.
    func testQuietHoursOnThisIPhone() {
        let app = XCUIApplication.russian(demo: "settings")
        let row = app.element("settingsWho")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("круглые сутки"), row.label)
        row.tap()
        let quiet = app.switches["quietHours"]
        XCTAssertTrue(quiet.waitForExistence(timeout: 5))
        let knob = quiet.switches.firstMatch
        (knob.exists ? knob : quiet).tap()
        XCTAssertTrue(app.element("quietFrom").waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("тихо 23:00–08:00"), row.label)
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
        // iOS 18 may ask first: «Открыть в “Love Around”?».
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for title in ["Открыть", "Open"] {
            let open = springboard.buttons[title]
            if open.waitForExistence(timeout: 2) {
                open.tap()
                break
            }
        }
        let code = app.element("pairCode")
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertEqual(code.value as? String, "482913")
        XCTAssertTrue(app.element("confirmPairing").waitForExistence(timeout: 5))
    }

    /// A device's card: who can reach it. Quiet hours off shows at once in
    /// the summary.
    func testDeviceCardQuietHoursOff() {
        let app = XCUIApplication.russian(demo: "toys")
        app.openTab("Игрушки")
        let lamp = app.element("device-d2")
        XCTAssertTrue(lamp.waitForExistence(timeout: 5))
        lamp.tap()
        let who = app.element("deviceWho")
        XCTAssertTrue(who.waitForExistence(timeout: 5))
        XCTAssertTrue(who.label.contains("тихо 23:00–08:00"), who.label)
        who.tap()
        let quiet = app.switches["quietHours"]
        XCTAssertTrue(quiet.waitForExistence(timeout: 5))
        XCTAssertEqual(quiet.value as? String, "1")
        XCTAssertTrue(app.element("quietFrom").exists)
        let knob = quiet.switches.firstMatch
        (knob.exists ? knob : quiet).tap()
        XCTAssertEqual(quiet.value as? String, "0")
        XCTAssertFalse(app.element("quietFrom").waitForExistence(timeout: 1))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(who.waitForExistence(timeout: 5))
        XCTAssertTrue(who.label.contains("круглые сутки"), who.label)
    }

    /// Everything off is fine: the device stays and does nothing.
    func testDeviceCanDoNothing() {
        let app = XCUIApplication.russian(demo: "toys")
        app.openTab("Игрушки")
        let watch = app.element("device-d1")
        XCTAssertTrue(watch.waitForExistence(timeout: 5))
        watch.tap()
        let does = app.element("deviceDoes")
        XCTAssertTrue(does.waitForExistence(timeout: 5))
        does.tap()
        for id in ["doesReceive", "doesSend"] {
            let toggle = app.switches[id]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            let knob = toggle.switches.firstMatch
            (knob.exists ? knob : toggle).tap()
            XCTAssertEqual(toggle.value as? String, "0", id)
        }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(does.waitForExistence(timeout: 5))
        XCTAssertTrue(does.label.contains("Ничего не делает"), does.label)
    }

    /// A paired lamp asked only to receive: sending can't be switched on.
    func testPairedDeviceKeepsToWhatItAskedFor() {
        let app = XCUIApplication.russian(demo: "deviceDoes")
        let send = app.switches["doesSend"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        XCTAssertFalse(send.isEnabled)
        XCTAssertTrue(app.switches["doesReceive"].isEnabled)
    }

    /// A board's new token: asked first, then shown once.
    func testBoardGetsANewToken() {
        let app = XCUIApplication.russian(demo: "deviceBoard")
        let new = app.element("newToken")
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        new.tap()
        let issue = app.alerts.buttons["Выпустить"]
        XCTAssertTrue(issue.waitForExistence(timeout: 5))
        issue.tap()
        XCTAssertTrue(app.element("newTokenValue").waitForExistence(timeout: 5))
        app.element("tokenDone").tap()
        XCTAssertTrue(new.waitForExistence(timeout: 5))
    }

    func testRenameDevice() {
        let app = XCUIApplication.russian(demo: "deviceBoard")
        let name = app.element("deviceName")
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        let field = app.textFields["deviceNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.clearAndType("Кнопка у кровати")
        app.element("saveName").tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(name.label.contains("Кнопка у кровати"), name.label)
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

extension XCUIElement {
    /// Replaces a text field's text.
    func clearAndType(_ text: String) {
        if let old = value as? String, !old.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        typeText(text)
    }
}
