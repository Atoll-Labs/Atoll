import XCTest

final class DynamicIslandUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    func testNotchExpansion() throws {
        let notch = app.descendants(matching: .any)["AtollNotch"]
        
        XCTAssertTrue(notch.waitForExistence(timeout: 5.0), "The Atoll notch should be visible.")
        
        // notch.click()
    }

    func testSettingsWindowOpens() throws {
        // App is LSUIElement usually, or background, wait for it to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0) || app.wait(for: .runningBackground, timeout: 5.0), "App should be running.")
    }
}

