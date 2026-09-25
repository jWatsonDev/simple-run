import XCTest

/// Renders the post-run screen with the debug demo run and saves screenshots to SCREENSHOT_DIR.
final class DetailScreenshotUITests: XCTestCase {
    func testDetailScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoActivity"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let hosts = [app, springboard, XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")]
        let row = app.buttons.containing(NSPredicate(format: "label CONTAINS '4.12 mi'")).firstMatch
        for _ in 0..<20 where !(row.exists && row.isHittable) {
            if springboard.buttons["Allow While Using App"].exists { springboard.buttons["Allow While Using App"].tap() }
            for host in hosts where host.descendants(matching: .any)["Turn On All"].firstMatch.exists {
                host.descendants(matching: .any)["Turn On All"].firstMatch.tap()
                host.buttons["Allow"].firstMatch.tap()
            }
            sleep(1)
        }
        row.tap()
        sleep(3)
        shot("detail-1")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("detail-2")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("detail-3")
        app.swipeUp(velocity: .fast)
        sleep(1)
        shot("detail-4")
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
