# Feed gesture regression checks

Run the shared **FeedGestures** scheme against a dedicated iPhone Simulator:

```sh
xcodebuild -project apple/DecisionInbox.xcodeproj -scheme FeedGestures \
  -destination 'platform=iOS Simulator,id=YOUR_QA_DEVICE_ID' \
  -packageAuthorizationProvider netrc -parallel-testing-enabled NO test
```

The suite launches `-sampleFeed`, which uses synthetic mail and skips authenticated startup. It swipes from the middle of the first post and asserts that the card actually moves at least 100 points without opening a thread. It also checks scrolling after Feed retap, after a thread closes, after returning from Saved, and while the Rive refresh is working. A normal card tap must still open mail. Each successful scenario attaches a screenshot; Xcode also records the interaction.

This suite reproduced the September 21 regression before its repair: the card-wide simultaneous long press prevented the parent pan, even though the long press never completed. Do not replace these gestures with `scrollTo` or view-model-only checks; those bypass gesture recognition. Keep button feedback scoped to its individual control.

The test target is separate from the shipping app and excluded from release archives. The existing command-line model suites remain under `apple/tests`.

The September 26 regression checks also scroll whole cards above the viewport, return to the top, and assert both the retained card's **Read** state and a smaller **TODAY** count. The same checks run while refresh is held open. Switching away/back then removes the confirmed-read card. These assertions distinguish a functioning pan from a functioning scroll-to-read pipeline.

The September 27 checks tap the genuine arrival bubble from both today's mail and the Earlier section. Historical recovery alone must never create a NEW bubble; mixed batches announce only genuine arrivals. The previous test expecting navigation into Yesterday was superseded after the user's recording showed that behavior was incorrect. They verify the announced card stays unread during navigation, can actually be opened, and allows another swipe and return to top. Fast refresh is exercised with and without arrivals: checking must be visible, its result must distinguish the outcomes, and fetched mail must be in the feed. Combined SwiftUI accessibility elements can report `isHittable == false` for a visible body; these tests verify its viewport position and then deliver an actual tap rather than relying on that flag.

`testRefreshKeepsAnimatingAfterTemporaryDrawableMiss` injects Rive's recoverable `noDrawable` event through the real illustration error handler, holds the sample checking state, and compares twelve crops of the robot pixels. The crop excludes native text, the clock and feed. It fails against the former fatal fallback policy even though the checking label is correct. Retain and review native video for the fast arrival/no-arrival tests as well: status assertions alone cannot establish that the authored motion played.

`RealMailboxTests` is separate and skips unless the **test runner** environment contains `DI_REAL_MAIL_QA=1`. Run it only on an authenticated QA Simulator with authorization to mark real mail read. Its DEBUG launch flag stages one existing unread message from TODAY with a synthetic in-memory arrival time and positions the feed; this checks navigation, not arrival classification. XCTest then taps the real bubble, opens the announced mail, verifies confirmed Read, swipes, returns to top, pulls to refresh, and verifies the read leaves the new session. It sends, deletes and archives nothing. This controls arrival timing; it does not claim to test delivery of a newly sent email. Real-mail screenshots and videos stay local and must not be committed or uploaded to Figma.

For a `test-without-building` run, copy the generated `.xctestrun` file beside the original, set `DecisionInboxUITests.EnvironmentVariables.DI_REAL_MAIL_QA` to `1`, and select only `RealMailboxTests/testAnnouncedMailOpensAndRefreshCompletes`. Setting `SystemAttachmentLifetime` to `keepAlways` retains the native recording for motion review. The default synthetic suite requires no account and never opts into this real-mail check.
