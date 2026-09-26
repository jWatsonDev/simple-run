import XCTest

/// Captures App Store screenshots from the debug demo data. Saves PNGs to SCREENSHOT_DIR.
final class AppStoreScreenshotsUITests: XCTestCase {
    private var app: XCUIApplication!

    func testCaptureAppStoreScreenshots() throws {
        app = XCUIApplication()
        app.launchArguments = ["-demoActivity"]
        app.launch()
        grantPermissions()

        let firstRow = app.buttons.containing(NSPredicate(format: "label CONTAINS '4.12 mi'")).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10))
        sleep(2)
        shot("05-home")

        firstRow.tap()
        sleep(4) // map tiles
        shot("01-score")

        scroll(by: 0.62)
        shot("02-why")

        scroll(by: 0.78)
        shot("03-charts")

        scroll(by: 0.5)
        shot("04-zones")

        app.navigationBars.buttons["Share"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 15))
        sleep(2)
        shot("06-share")
    }

    private func scroll(by fraction: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85 - fraction))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)
    }

    private func grantPermissions() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let hosts = [app!, springboard, XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")]
        let start = app.buttons["Start Run"]
        for _ in 0..<20 where !(start.exists && start.isHittable) {
            if springboard.buttons["Allow While Using App"].exists { springboard.buttons["Allow While Using App"].tap() }
            for host in hosts where host.descendants(matching: .any)["Turn On All"].firstMatch.exists {
                host.descendants(matching: .any)["Turn On All"].firstMatch.tap()
                host.buttons["Allow"].firstMatch.tap()
            }
            sleep(1)
        }
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
