import XCTest

/// Uses synthetic mail and native touch delivery. scrollTo alone cannot catch
/// a row recognizer stealing the scroll view's pan.
final class FeedGestureTests: XCTestCase {
    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sampleFeed"] + extra
        app.launch()
        XCTAssertTrue(firstCard(in: app).waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func firstCard(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Priya Raman, needs you.")).firstMatch
    }

    @MainActor
    private func swipeCard(in app: XCUIApplication, evidence: String) {
        let first = firstCard(in: app)
        let before = first.frame.minY
        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: -220))
        start.press(forDuration: 0.05, thenDragTo: end)
        let moved = NSPredicate { _, _ in !first.exists || first.frame.minY < before - 100 }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.tabBars.buttons["Feed"].isHittable, "Swipe must not open the thread")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = evidence
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSwipeStartingOnCardMovesFeedAndAfterReturnToTop() {
        let app = launch()
        let top = firstCard(in: app).frame.minY
        swipeCard(in: app, evidence: "Card-origin swipe")
        app.tabBars.buttons["Feed"].tap()
        expectation(for: NSPredicate { _, _ in abs(self.firstCard(in: app).frame.minY - top) < 15 }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        swipeCard(in: app, evidence: "Swipe after Feed retap")
    }

    @MainActor
    func testSwipeAfterOpeningAndClosingThread() {
        let app = launch()
        firstCard(in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5), "A normal tap still opens mail")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 5))
        swipeCard(in: app, evidence: "Swipe after thread return")
    }

    @MainActor
    func testSwipeAfterTabChange() {
        let app = launch()
        app.tabBars.buttons["Saved"].tap()
        app.tabBars.buttons["Feed"].tap()
        swipeCard(in: app, evidence: "Swipe after tab return")
    }

    @MainActor
    private func scrollPastFirstCard(in app: XCUIApplication) {
        func todayRemaining() -> Int? {
            let label = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Today, ")).firstMatch.label
            return label.split(separator: " ").compactMap { Int($0) }.first
        }
        let before = todayRemaining()
        XCTAssertNotNil(before, "The section count must be known before scrolling")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.78))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.22))
        for _ in 0..<3 { start.press(forDuration: 0.05, thenDragTo: end) }
        app.tabBars.buttons["Feed"].tap()
        XCTAssertTrue(firstCard(in: app).waitForExistence(timeout: 5))
        expectation(for: NSPredicate { _, _ in self.firstCard(in: app).value as? String == "Read" }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertLessThan(todayRemaining() ?? Int.max, before ?? 0, "Scroll-past reduces the visible section count")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Confirmed read and reduced count, with card retained"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testScrollPastMarksReadAndRemovesOnNextVisit() {
        let app = launch()
        scrollPastFirstCard(in: app)
        app.tabBars.buttons["Saved"].tap()
        app.tabBars.buttons["Feed"].tap()
        XCTAssertFalse(firstCard(in: app).exists, "Read cards leave only on the next visit")
    }

    @MainActor
    func testScrollPastWhileRefreshIsWorkingStillCounts() {
        let app = launch(["-sampleRefresh"])
        XCTAssertTrue(app.staticTexts["CHECKING YOUR MAILBOX…"].waitForExistence(timeout: 5))
        scrollPastFirstCard(in: app)
    }

    @MainActor
    func testSwipeWhileIllustratedRefreshIsWorking() {
        let app = launch(["-sampleRefresh"])
        XCTAssertTrue(app.staticTexts["CHECKING YOUR MAILBOX…"].waitForExistence(timeout: 5))
        swipeCard(in: app, evidence: "Swipe with active Rive refresh")
    }

    @MainActor
    func testCompletedActivityHidesBannerAndKeepsReceipt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-sampleActivity", "-sampleActivityReturned", "-sampleActivityExpanded"]
        app.launch()
        let completed = app.buttons["I completed it on the sender’s page"]
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        for _ in 0..<3 where !completed.isHittable { app.swipeUp() }
        completed.tap()
        app.buttons["Mark complete"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Hide activity summary"].exists, "Completed work leaves the global banner")
        app.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Marked complete by you"].waitForExistence(timeout: 5), "The honest receipt remains in Activity")
    }
}
