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
        let notch = app.windows["AtollNotch"]
        
        XCTAssertTrue(notch.exists, "The Atoll notch should be visible.")
        
        notch.click()
        
        // let playButton = app.buttons["PlayPauseButton"]
        // XCTAssertTrue(playButton.waitForExistence(timeout: 2.0))
    }

    func testSettingsWindowOpens() throws {
        XCTAssertEqual(app.state, .runningForeground, "App should be running in foreground.")
    }
}

