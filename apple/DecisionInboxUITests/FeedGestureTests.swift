import XCTest
import UIKit

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
    private func assertBubbleShowsArrival(fromEarlier: Bool) {
        let app = launch(["-samplePendingArrival"] + (fromEarlier ? ["-sampleHistoryRecovery"] : []))
        app.swipeUp()
        if fromEarlier {
            for _ in 0..<2 { app.swipeUp() }
            XCTAssertTrue(app.staticTexts["Older emails synced."].exists, "The reader has reached the older-mail end")
        }
        let bubble = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "1 new emails, from Arrival Test")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        bubble.tap()
        let arrival = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Arrival Test, fyi.")).firstMatch
        // A combined SwiftUI accessibility element can report non-hittable
        // despite a visible, tappable body. Verify its viewport and then tap it.
        expectation(for: NSPredicate { _, _ in
            arrival.exists && arrival.frame.midY > app.frame.minY + 100
                && arrival.frame.midY < app.frame.maxY - 100
        }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(arrival.value as? String, "Unread", "Bubble navigation must not mark the new email read")
        XCTAssertFalse(bubble.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = fromEarlier ? "Real arrival from Earlier returns to top" : "Bubble to today arrival"
        shot.lifetime = .keepAlways
        add(shot)
        arrival.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 5), "The announced card must actually open")
        app.buttons["Back"].tap()
        let before = arrival.frame.minY
        app.swipeUp()
        expectation(for: NSPredicate { _, _ in !arrival.exists || arrival.frame.minY < before - 80 }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["Feed"].tap()
    }

    @MainActor func testBubbleShowsTodayArrival() { assertBubbleShowsArrival(fromEarlier: false) }
    @MainActor func testRealArrivalFromEarlierReturnsToTop() { assertBubbleShowsArrival(fromEarlier: true) }

    @MainActor func testHistoricalRecoveryNeverCreatesNewBubble() {
        let app = launch(["-sampleHistoryRecovery"])
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "new emails, from")).firstMatch.exists)
        let include = app.buttons["Refresh to include them"]
        XCTAssertTrue(include.waitForExistence(timeout: 5), "Recovered history stays available without a false NEW announcement")
        include.tap()
        let history = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "History Test, fyi.")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 5), "Refresh includes the recovered unread email")
        XCTAssertTrue(app.staticTexts["NO NEW EMAILS"].exists || app.staticTexts["NO NEW EMAILS"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertFastRefresh(arrival: Bool) {
        let app = launch(arrival ? ["-sampleRefreshArrival"] : [])
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.85)))
        let checking = app.staticTexts["CHECKING YOUR MAILBOX…"]
        XCTAssertTrue(checking.exists || checking.waitForExistence(timeout: 3), "Fast responses still show the checking sequence")
        let result = app.staticTexts[arrival ? "1 NEW EMAIL" : "NO NEW EMAILS"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "The result distinguishes arrivals from no arrivals")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = arrival ? "Refresh arrival outcome" : "Refresh no-arrival outcome"
        shot.lifetime = .keepAlways
        add(shot)
        expectation(for: NSPredicate { _, _ in !result.exists }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        if arrival {
            let post = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Arrival Test, fyi.")).firstMatch
            XCTAssertTrue(post.exists && app.frame.contains(CGPoint(x: post.frame.midX, y: post.frame.midY)),
                "Refresh reveals the email it found without another bubble tap")
        }
    }

    @MainActor func testFastRefreshShowsNoArrivalSequence() { assertFastRefresh(arrival: false) }
    @MainActor func testFastRefreshShowsArrivalSequence() { assertFastRefresh(arrival: true) }

    @MainActor
    func testRefreshKeepsAnimatingAfterTemporaryDrawableMiss() {
        let app = launch(["-sampleRefresh", "-sampleDrawableMiss"])
        XCTAssertTrue(app.staticTexts["CHECKING YOUR MAILBOX…"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.25)
        // Compare only the robot area, excluding the clock, caption and feed.
        // Native status text alone cannot prove the GPU player is advancing.
        var frames = Set<Data>()
        for _ in 0..<12 {
            let shot = app.screenshot()
            if let image = shot.image.cgImage {
                let rect = CGRect(x: Double(image.width) * 0.25, y: Double(image.height) * 0.055,
                                  width: Double(image.width) * 0.5, height: Double(image.height) * 0.095)
                if let crop = image.cropping(to: rect), let data = UIImage(cgImage: crop).pngData() {
                    frames.insert(data)
                }
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        XCTAssertGreaterThan(frames.count, 1, "A missed drawable must not turn the checking animation into a still image")
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
    func testImageArrivingDuringSwipeDoesNotDiscardReads() {
        let app = launch(["-sampleLatePromo"])
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.82))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        app.tabBars.buttons["Feed"].tap()
        let first = firstCard(in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        expectation(for: NSPredicate { _, _ in first.value as? String == "Read" }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["Saved"].tap()
        app.tabBars.buttons["Feed"].tap()
        XCTAssertFalse(firstCard(in: app).exists, "An image finishing must not lose a proven read")
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
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Completed banner dismissed; user-reported receipt retained"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
