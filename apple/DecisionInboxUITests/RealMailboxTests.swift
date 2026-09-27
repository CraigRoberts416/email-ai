import XCTest

/// Opt in only on an already authenticated QA Simulator. This opens one real
/// message (marking it read), and scrolls a few cards. No mail is sent or filed.
final class RealMailboxTests: XCTestCase {
    @MainActor
    func testAnnouncedMailOpensAndRefreshCompletes() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DI_REAL_MAIL_QA"] == "1",
                          "Requires explicit real-mail QA and an authenticated Simulator")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-stageRealArrivalForTouchTest"]
        app.launch()
        let cards = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "feed.card."))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 40))
        let bubble = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "new emails, from ")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 40))
        let sender = String(bubble.label.components(separatedBy: "from ").last!.components(separatedBy: ", ").first!)
        bubble.tap()
        let arrival = cards.matching(NSPredicate(format: "label BEGINSWITH %@", sender + ", ")).firstMatch
        XCTAssertTrue(arrival.waitForExistence(timeout: 10))
        let key = arrival.identifier
        XCTAssertEqual(arrival.value as? String, "Unread")
        XCTAssertLessThan(arrival.frame.minY, app.frame.maxY - 150)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Real mailbox — announced arrival"
        shot.lifetime = .keepAlways
        add(shot)
        // Touch the reading surface below its avatar and above its controls.
        arrival.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.4)).tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 10))
        app.buttons["Back"].tap()
        let retained = app.descendants(matching: .any).matching(identifier: key).firstMatch
        expectation(for: NSPredicate { _, _ in retained.exists && retained.value as? String == "Read" }, evaluatedWith: nil)
        waitForExpectations(timeout: 25)
        let before = retained.frame.minY
        app.swipeUp()
        expectation(for: NSPredicate { _, _ in !retained.exists || retained.frame.minY < before - 80 }, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["Feed"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.85)))
        let result = app.staticTexts.matching(NSPredicate(format: "label == %@ OR label MATCHES %@", "NO NEW EMAILS", "[0-9]+ NEW EMAILS?")).firstMatch
        XCTAssertTrue(result.exists || result.waitForExistence(timeout: 35), "Live refresh returns an honest successful outcome")
        XCTAssertFalse(retained.exists, "The refresh session removes the provider-confirmed read")
        let refreshed = XCTAttachment(screenshot: app.screenshot())
        refreshed.name = "Real mailbox — refresh outcome"
        refreshed.lifetime = .keepAlways
        add(refreshed)
    }
}
