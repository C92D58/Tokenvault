import XCTest

/// Acceptance tests for the iOS build. They drive the real app on a simulator with the vault
/// unlocked and seeded (`-uiTestUnlocked -uiTestSeed`), and start from a wiped store every run.
final class TokenVaultUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(seed: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        // Pin the UI language: the suite queries Chinese labels, so it must not depend on how the
        // simulator or the host Mac is configured. English is covered by the shared strings file.
        var args = ["-uiTestReset", "-uiTestUnlocked",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_Hant_TW",
                    // The app has its own language switch; pin it so a previous run's choice
                    // cannot turn the labels these tests query into English.
                    "-tv.language", "system"]
        if seed { args.append("-uiTestSeed") }
        app.launchArguments = args
        app.launch()
        return app
    }

    private func row(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.descendants(matching: .any)["token.\(name)"].firstMatch
    }

    /// Opens a tab without racing the floating tab bar's entrance animation.
    ///
    /// Tapping a tab item straight after launch intermittently fails with
    /// "Activation point invalid … {{-316, 795}}" — the bar is still animating in, so its frame is
    /// not yet where it will end up. Wait for the tab item, then retry until it is hittable.
    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 12), "tab \(name) should exist")
        for _ in 0..<8 {
            if tab.isHittable {
                tab.tap()
                return
            }
            usleep(300_000)
        }
        XCTFail("tab \(name) never became hittable")
    }


    // MARK: - Language

    /// The switch lives in the app, not in iOS Settings: picking English must relabel the whole
    /// UI on the spot, and picking Chinese must put it back.
    func testLanguageSwitchesInsideTheApp() {
        let app = launchApp()
        openTab(app, "設定")

        let languageRow = app.descendants(matching: .any)["settings.language"].firstMatch
        XCTAssertTrue(languageRow.waitForExistence(timeout: 10), "the language row should exist")
        languageRow.tap()

        let english = app.buttons["English"].firstMatch.exists
            ? app.buttons["English"].firstMatch
            : app.menuItems["English"].firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 6), "the menu should offer English")
        english.tap()

        // The settings screen stays put and comes back in English.
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 8),
                      "the settings screen should be English right after the switch")
        // Section labels are drawn uppercased, so check the row copy instead.
        XCTAssertTrue(app.staticTexts["Unlock with biometrics"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Import secrets"].exists)
        XCTAssertTrue(app.staticTexts["APPEARANCE"].exists)

        // And back, so the suite and the next launch start in Chinese again. The tree was
        // re-identified a moment ago, so the row can swallow the first tap while it settles —
        // retry instead of failing on a rebuilt view.
        let rowAgain = app.descendants(matching: .any)["settings.language"].firstMatch
        XCTAssertTrue(rowAgain.waitForExistence(timeout: 8))
        var switchedBack = false
        for _ in 0..<4 {
            rowAgain.tap()
            let chinese = app.buttons["繁體中文"].firstMatch.exists
                ? app.buttons["繁體中文"].firstMatch
                : app.menuItems["繁體中文"].firstMatch
            if chinese.waitForExistence(timeout: 3) {
                chinese.tap()
                switchedBack = true
                break
            }
        }
        XCTAssertTrue(switchedBack, "the language menu should reopen after the switch")
        XCTAssertTrue(app.staticTexts["設定"].waitForExistence(timeout: 8),
                      "the settings screen should be Chinese again")
    }

    // MARK: - Vault

    func testSeededVaultListsTokens() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["vault.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(row(app, "OpenAI 專案金鑰").waitForExistence(timeout: 5),
                      "the seeded OpenAI token should be listed")
        XCTAssertTrue(row(app, "GitHub 個人存取權杖").exists)
    }

    func testSearchNarrowsTheList() {
        let app = launchApp()
        let search = app.textFields["vault.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("GitHub")

        XCTAssertTrue(row(app, "GitHub 個人存取權杖").waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, "OpenAI 專案金鑰").exists,
                       "search should filter the unrelated token out")
    }

    func testDetailSheetShowsSecretAndCopies() {
        let app = launchApp()
        let openAI = row(app, "OpenAI 專案金鑰")
        XCTAssertTrue(openAI.waitForExistence(timeout: 10))
        openAI.tap()

        let value = app.staticTexts["detail.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertTrue(value.label.contains("••"), "the value must start masked")

        app.buttons["detail.reveal"].tap()
        XCTAssertFalse(value.label.contains("••"), "revealing must show the plaintext")

        app.buttons["detail.copy"].tap()
        let toast = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "已複製")).firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 4), "copying should confirm with a toast")
    }

    func testAddTokenEndsUpInTheList() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["vault.add"].waitForExistence(timeout: 10))
        app.buttons["vault.add"].tap()

        let nameField = app.textFields["editor.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("測試密鑰 ABC")

        let valueField = app.secureTextFields["editor.value"].exists
            ? app.secureTextFields["editor.value"]
            : app.textFields["editor.value"]
        valueField.tap()
        valueField.typeText("sk-test-0123456789")

        app.buttons["editor.save"].tap()
        XCTAssertTrue(row(app, "測試密鑰 ABC").waitForExistence(timeout: 6),
                      "the new token should appear in the vault")
    }

    // MARK: - Tools

    func testGeneratorProducesRequestedLength() {
        let app = launchApp()
        openTab(app, "工具")
        XCTAssertTrue(app.staticTexts["tools.title"].waitForExistence(timeout: 8))

        let output = app.staticTexts["tools.generated"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertEqual(output.label.count, 32, "default length is 32 characters")
    }

    /// Decodes the seeded JWT through the real path a user takes: search → detail → 解碼.
    ///
    /// Typing into the tools tab's JWT field was abandoned as a test: the field sits inside a
    /// scrolled card and `typeText` intermittently fails with "Neither element nor any descendant
    /// has keyboard focus", which says nothing about the decoder.
    func testJWTDecoderReadsAClaim() {
        let app = launchApp()

        let search = app.textFields["vault.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("JWT")

        let jwtRow = row(app, "JWT 範例（除錯用）")
        XCTAssertTrue(jwtRow.waitForExistence(timeout: 6), "searching JWT should surface the demo token")
        jwtRow.tap()

        let decode = app.buttons["解碼"].firstMatch
        XCTAssertTrue(decode.waitForExistence(timeout: 6), "the JWT card offers 解碼")
        decode.tap()

        XCTAssertTrue(app.staticTexts["sub"].waitForExistence(timeout: 6),
                      "the decoded payload should list the sub claim")
        XCTAssertTrue(app.staticTexts["role"].waitForExistence(timeout: 4),
                      "and the role claim alongside it")
    }

    // MARK: - Settings

    func testSettingsShowsSecurityAndAbout() {
        let app = launchApp()
        openTab(app, "設定")
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["生物辨識解鎖"].exists)
        XCTAssertTrue(app.staticTexts["開發者"].exists)
        XCTAssertTrue(app.staticTexts["TokenVault"].exists)
    }

    func testLockReturnsToTheLockScreen() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["vault.lock"].waitForExistence(timeout: 10))
        app.buttons["vault.lock"].tap()
        XCTAssertTrue(app.buttons["lock.unlock"].waitForExistence(timeout: 5),
                      "locking from the vault should present the lock screen")
    }

    // MARK: - Layout

    /// The floating tab bar is translucent and overlays the list, so the last card must be able to
    /// scroll clear of it. Measured from frames, not from a screenshot.
    func testVaultListClearsTheFloatingTabBar() {
        let app = launchApp()
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10), "the vault list should be up")

        for _ in 0..<5 { list.swipeUp(velocity: .slow) }
        usleep(700_000)

        let lastCard = row(app, "Claude API")
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(lastCard.exists, "the bottom-most seeded token should exist")
        XCTAssertTrue(tabBar.exists)
        XCTAssertLessThanOrEqual(lastCard.frame.maxY, tabBar.frame.minY + 1,
                                 "the last card must end above the floating tab bar")
    }

    // MARK: - Screenshot tour (attachments, not assertions)

    func testScreenshotTour() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["vault.title"].waitForExistence(timeout: 10))
        capture(app, "01-vault")

        let openAI = row(app, "OpenAI 專案金鑰")
        if openAI.waitForExistence(timeout: 5) {
            openAI.tap()
            _ = app.staticTexts["detail.value"].waitForExistence(timeout: 5)
            capture(app, "02-detail")
            app.buttons["關閉"].firstMatch.tap()
            // The sheet is dismissed with an animation; the vault header is only hittable after it.
            XCTAssertTrue(app.buttons["vault.add"].waitForExistence(timeout: 8))
        }

        app.buttons["vault.add"].tap()
        _ = app.textFields["editor.name"].waitForExistence(timeout: 5)
        capture(app, "03-editor")
        app.buttons["取消"].firstMatch.tap()

        openTab(app, "工具")
        _ = app.staticTexts["tools.title"].waitForExistence(timeout: 8)
        capture(app, "04-tools")

        openTab(app, "設定")
        _ = app.staticTexts["settings.title"].waitForExistence(timeout: 8)
        capture(app, "05-settings")

        // The appearance switch must take effect on the spot — same screen, no relaunch.
        if app.buttons["深色"].exists {
            app.buttons["深色"].tap()
            capture(app, "05b-settings-dark")
            app.buttons["淺色"].tap()
            capture(app, "05c-settings-light")
            app.buttons["跟隨系統"].tap()
        }

        openTab(app, "日誌")
        usleep(900_000)
        capture(app, "06-log")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        usleep(900_000) // let the render settle before the frame is sampled
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
