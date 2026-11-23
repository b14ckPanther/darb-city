import XCTest

/// Opens a need's page the way a person does (a tap on its tile), taps back, and times how long until home is back.
@MainActor
final class BackTimingTests: XCTestCase {
    func testBackIsQuick() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-darbOnboarded", "YES", "-darbSkipSplash", "YES", "-darbTime", "12:30", "-darbPerf", "YES"] + (ProcessInfo.processInfo.environment["STILL"] == "1" ? ["-darbStillArt", "YES"] : [])
        app.launch()
        let food = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'אוכל' AND label CONTAINS 'דקות'")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        sleep(3)
        let t0 = Date()
        food.tap()
        let back = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "חזרה")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        print("DARBTIME open-to-back-visible \(Date().timeIntervalSince(t0))")
        let t1 = Date()
        back.tap()
        print("DARBTIME back-tap-returned \(Date().timeIntervalSince(t1))")
        XCTAssertTrue(food.waitForExistence(timeout: 15))
        let deadline = Date().addingTimeInterval(15)
        while back.exists, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        print("DARBTIME back-to-home \(Date().timeIntervalSince(t1))")
    }
}
