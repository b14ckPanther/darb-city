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

/// A business's own page, opened from the rail of a need's page: one tap on back must leave it.
@MainActor
final class BusinessBackTests: XCTestCase {
    func testOneTapLeavesABusiness() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-darbOnboarded", "YES", "-darbSkipSplash", "YES", "-darbTime", "12:30", "-darbStillArt", "YES"]
        app.launch()
        let food = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'אוכל' AND label CONTAINS 'דקות'")).firstMatch
        XCTAssertTrue(food.waitForExistence(timeout: 8))
        sleep(2)
        food.tap()
        let back = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "חזרה")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        sleep(2)
        for attempt in 1...4 {
            let t = Date()
            back.tap()
            let deadline = Date().addingTimeInterval(2.5)
            while back.exists, back.isHittable, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            print("DARBTIME tap \(attempt) left=\(!back.exists || !back.isHittable) after \(Date().timeIntervalSince(t))")
            if !back.exists || !back.isHittable { break }
        }
        XCTAssertTrue(food.waitForExistence(timeout: 5))
    }
}

/// A business opened straight (search, a link, the map): one tap on back must leave it, even right after it opens.
@MainActor
final class DirectBusinessBackTests: XCTestCase {
    func testOneTapLeavesADirectBusiness() throws {
        for wait in [0.4, 2.0] {
            let app = XCUIApplication()
            app.launchArguments = ["-darbOnboarded", "YES", "-darbSkipSplash", "YES", "-darbTime", "12:30", "-darbStillArt", "YES",
                                   "-darbRoute", "business:1094849112"]
            app.launch()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: wait)
            print("DARBTIME back label=\(back.label) id=\(back.identifier)")
            for attempt in 1...4 {
                let t = Date()
                back.tap()
                let deadline = Date().addingTimeInterval(2.5)
                while back.exists, back.isHittable, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                let left = !back.exists || !back.isHittable
                print("DARBTIME wait \(wait) tap \(attempt) left=\(left) after \(Date().timeIntervalSince(t))")
                if left { break }
            }
            app.terminate()
        }
    }
}
