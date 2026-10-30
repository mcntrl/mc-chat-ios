//
// Mission Control (MIS-103, MC-NOE2EE): proves a fresh install goes Sign in → room list with no
// verification / recovery / backup prompts, and that Settings has no Encryption section.
// Launches the app WITHOUT IS_RUNNING_INTEGRATION_TESTS so the real onboarding flow runs.
// Credentials come from the runner environment (TEST_RUNNER_MC_QA_USERNAME / TEST_RUNNER_MC_QA_PASSWORD
// in CI); they are never attached or logged.
//

import XCTest

@MainActor
class MCNoPromptsTests: XCTestCase {
    private static let forbidden = ["Confirm it's you", "Confirm it’s you", "Confirm your identity", "Verify this",
                                    "Verify session", "Verify user", "Set up recovery", "recovery key", "Recovery key",
                                    "Secure backup", "Key storage", "Chat backup", "Encryption", "Reset identity",
                                    "Cross-signing", "cross-signing"]
    /// Non-encryption onboarding steps we may pass through; each one is screenshotted and reported.
    private static let skipLabels = ["No thanks", "Not now", "Skip", "Don’t Allow", "Don't Allow", "Maybe later"]

    private var app: XCUIApplication!
    private var shots = 0

    private func env(_ key: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? ""
    }

    private func shot(_ name: String) {
        shots += 1
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = String(format: "%02d-%@", shots, name)
        a.lifetime = .keepAlways
        add(a)
    }

    private func forbiddenOnScreen() -> String? {
        for phrase in Self.forbidden {
            let p = NSPredicate(format: "label CONTAINS %@", phrase)
            if app.staticTexts.matching(p).firstMatch.exists || app.buttons.matching(p).firstMatch.exists {
                return phrase
            }
        }
        return nil
    }

    func testFreshInstallSignInGoesStraightToRoomList() throws {
        continueAfterFailure = false
        let username = env("MC_QA_USERNAME"), password = env("MC_QA_PASSWORD")
        try XCTSkipIf(username.isEmpty || password.isEmpty, "MC_QA_USERNAME / MC_QA_PASSWORD not set")

        app = XCUIApplication()
        app.launch()

        let signIn = app.buttons[A11yIdentifiers.authenticationStartScreen.signIn]
        XCTAssertTrue(signIn.waitForExistence(timeout: 30))
        shot("start-screen")
        signIn.tap()

        let serverContinue = app.buttons[A11yIdentifiers.serverConfirmationScreen.continue]
        if serverContinue.waitForExistence(timeout: 8) {
            shot("server-confirmation")
            serverContinue.tap()
        }

        let user = app.textFields[A11yIdentifiers.loginScreen.emailUsername]
        XCTAssertTrue(user.waitForExistence(timeout: 60), "Password login screen did not appear")
        user.tap()
        user.typeText(username)
        let pass = app.secureTextFields[A11yIdentifiers.loginScreen.password]
        XCTAssertTrue(pass.waitForExistence(timeout: 10))
        pass.tap()
        pass.typeText(password)
        shot("login-filled") // password field is masked
        app.buttons[A11yIdentifiers.loginScreen.continue].tap()

        // Between login and the room list: record every distinct screen, fail on any encryption prompt.
        let home = app.buttons[A11yIdentifiers.homeScreen.userAvatar]
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(300)
        var intermediate = 0
        while !home.exists, Date() < deadline {
            if let phrase = forbiddenOnScreen() {
                shot("FORBIDDEN-\(phrase)")
                XCTFail("Encryption/verification prompt shown after login: \(phrase)")
                return
            }
            if app.buttons["Save Password"].exists || app.buttons["Not Now"].exists {
                app.buttons["Not Now"].firstMatch.tap()
            }
            for label in Self.skipLabels {
                let b = app.buttons[label].firstMatch
                let s = springboard.buttons[label].firstMatch
                if b.exists || s.exists {
                    intermediate += 1
                    shot("intermediate-\(intermediate)-\(label.replacingOccurrences(of: " ", with: "_"))")
                    (b.exists ? b : s).tap()
                    break
                }
            }
            _ = home.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(home.exists, "Room list never appeared")
        sleep(6) // let the room list and any banners settle
        if let phrase = forbiddenOnScreen() {
            shot("FORBIDDEN-home-\(phrase)")
            XCTFail("Encryption/verification banner on the room list: \(phrase)")
        }
        shot("room-list")
        XCTAssertFalse(app.buttons[A11yIdentifiers.homeScreen.recoveryKeyConfirmationBannerContinue].exists)

        // Settings: no Encryption / secure backup row.
        home.tap()
        let logout = app.buttons[A11yIdentifiers.settingsScreen.logout]
        XCTAssertTrue(logout.waitForExistence(timeout: 20))
        shot("settings")
        XCTAssertFalse(app.buttons[A11yIdentifiers.settingsScreen.secureBackup].exists, "Settings still shows Encryption")
        app.swipeUp()
        shot("settings-bottom")
        XCTAssertFalse(app.buttons[A11yIdentifiers.settingsScreen.secureBackup].exists, "Settings still shows Encryption")

        // Sign out: plain confirmation only (also removes the CI device from rocket-qa).
        logout.tap()
        let confirm = app.alerts.firstMatch.buttons[A11yIdentifiers.alertInfo.primaryButton].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No plain sign-out confirmation")
        shot("sign-out-confirmation")
        XCTAssertNil(forbiddenOnScreen(), "Sign-out shows recovery/backup warnings")
        confirm.tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 30))
        shot("signed-out")
    }
}
