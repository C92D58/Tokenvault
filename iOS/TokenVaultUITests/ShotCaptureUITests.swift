import XCTest

/// Marketing/screenshot capture only — assertions are limited to "the screen we need is up".
/// Not part of the acceptance suite's pass criteria; run it on its own with
/// `-only-testing:TokenVaultUITests/ShotCaptureUITests`.
final class ShotCaptureUITests: XCTestCase {

    private let screenshotSettle: useconds_t = 900_000

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureShots() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestUnlocked", "-uiTestSeed",
                               "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_Hant_TW"]
        app.launch()

        // 01 — vault list, several rows with PROD / DEV badges.
        XCTAssertTrue(app.staticTexts["vault.title"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.descendants(matching: .any)["token.OpenAI 專案金鑰"].firstMatch
            .waitForExistence(timeout: 10))
        capture(app, "01-list")

        // 02 — detail sheet, value still masked, env badge + copy button on screen.
        let openAI = app.descendants(matching: .any)["token.OpenAI 專案金鑰"].firstMatch
        openAI.tap()
        let value = app.staticTexts["detail.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        XCTAssertTrue(value.label.contains("••"), "detail must open masked")
        capture(app, "02-detail")

        let close = app.buttons["關閉"].firstMatch
        if close.waitForExistence(timeout: 5) { close.tap() }
        XCTAssertTrue(app.buttons["vault.add"].waitForExistence(timeout: 10))

        // 03 — key generator (工具 tab, generator card is the first surface).
        openTab(app, "工具")
        XCTAssertTrue(app.staticTexts["tools.title"].waitForExistence(timeout: 10))
        let generated = app.staticTexts["tools.generated"]
        XCTAssertTrue(generated.waitForExistence(timeout: 8))
        XCTAssertFalse(generated.label.isEmpty)
        capture(app, "03-generate")

        // 04 — lock screen. Relaunch stays locked so the branded lock screen is the whole frame.
        // The view asks for Face ID ~1.2 s after it appears, so the frame is sampled immediately.
        app.terminate()
        app.launchArguments = ["-uiTestLocked",
                               "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_Hant_TW"]
        app.launch()
        let unlock = app.buttons["lock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 25))
        usleep(200_000)
        capture(app, "04-lock", settle: false, settleAfter: 0)
    }

    private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "tab \(name) should exist")
        for _ in 0..<10 {
            if tab.isHittable {
                tab.tap()
                return
            }
            usleep(300_000)
        }
        XCTFail("tab \(name) never became hittable")
    }

    private func capture(_ app: XCUIApplication, _ name: String,
                         settle: Bool = true, settleAfter: useconds_t = 900_000) {
        if settle { usleep(screenshotSettle) }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if settleAfter > 0 { usleep(settleAfter) }
    }
}
