import XCTest

/// Walks the core flow on a simulator with a simulated GPS route. Screenshots land in SCREENSHOT_DIR if set.
final class FlowUITests: XCTestCase {
    func testRecordAndScoreRun() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        addUIInterruptionMonitor(withDescription: "Location") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app.launch()

        // Location prompt (springboard) then the HealthKit sheet (in-app).
        let allowLocation = springboard.buttons["Allow While Using App"]
        if allowLocation.waitForExistence(timeout: 5) { allowLocation.tap() }
        // The HealthKit sheet is hosted out of process, depending on iOS version.
        let hosts = [app, springboard, XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")]
        let start = app.buttons["Start Run"]
        for _ in 0..<20 where !(start.exists && start.isHittable) {
            for host in hosts {
                let turnOnAll = host.descendants(matching: .any)["Turn On All"].firstMatch
                if turnOnAll.exists {
                    turnOnAll.tap()
                    host.buttons["Allow"].firstMatch.tap()
                }
            }
            sleep(1)
        }
        if !start.isHittable, let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            let dump = hosts.map(\.debugDescription).joined(separator: "\n=====\n")
            try? dump.write(toFile: dir + "/tree.txt", atomically: true, encoding: .utf8)
        }

        XCTAssertTrue(app.buttons["Start Run"].waitForExistence(timeout: 10))
        shot("1-home")

        app.buttons["Start Run"].tap()
        XCTAssertTrue(app.buttons["Finish"].waitForExistence(timeout: 5))
        sleep(25)
        shot("2-recording")

        app.buttons["Finish"].tap()
        app.buttons["Finish & Save"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Drinks last night?"].waitForExistence(timeout: 20))
        shot("3-result")
        app.buttons["3+"].tap()
        sleep(1)
        shot("4-result-after-drinks")
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
