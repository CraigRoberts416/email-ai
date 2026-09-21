# Feed gesture repair and illustrated release — 1.0 (2609210445)

September 21, 2026. Supersedes the unuploaded `2609202100` archive. Includes the three original Rive artboards and application-state bindings described in [the illustrated release record](native-release-2609202100.md), plus the feed scrolling regression repair.

## Cause and correction

The interaction release added a simultaneous, 60-second `LongPressGesture` to every post to observe touch-down and tint its background. Despite never completing in an ordinary swipe, that recognizer prevented the enclosing SwiftUI scroll view from beginning its pan. The earlier prohibition on a row-level drag did not cover this new recognizer.

A native XCTest swipe beginning in the middle of the first synthetic post failed against the unchanged implementation on iOS 26.5. Removing only the row-wide hold and its pressed background made the same test pass. Individual buttons retain their existing press feedback, card taps still open mail, and the native context menu remains. The permanent top anchor, one-shot scroll requests, durable read queue and Rive bindings are preserved.

## Verification

- Native gesture suite on iOS 26.5: four tests passed. Covers card-origin swipe, return-to-top followed by another swipe, opening/closing a thread, tab return, and scrolling while the illustrated refresh is working.
- FeedStore production integration: 156 checks passed.
- iOS 26.4 gesture suite and distribution checks are pending at this recording.
- Tests use `-sampleFeed` synthetic mail, with a separate dedicated Simulator. No real send, unsubscribe, archive, or account disconnect is used.

The retained `FeedGestures` scheme runs genuine touch gestures; programmatic `scrollTo` is insufficient to catch this failure. See [test instructions](../apple/DecisionInboxUITests/README.md). Baseline failure: `/tmp/di-gesture-before.xcresult`; corrected suite: `/tmp/di-gesture-regression.xcresult`. Result bundles contain native event traces and screen recordings. Physical-device confirmation remains distinct from Simulator verification.

## Distribution

Release archive `2609210445` passed. Its bundle identifier/version, artwork checksum, bundled license and absence of DEBUG sample routes/UI-test bundles were verified. The command-line upload was rejected before transfer with `Failed to Use Accounts`: Xcode could not find an account with App Store Connect access for team `48X38356RX`. Organizer upload recovery is in progress. The corrected archive is retained at `~/Library/Developer/Xcode/Archives/2026-09-21/DecisionInbox 2026-09-21 04.45.xcarchive`. The backend remains the already-live `a6e9043`; this repair and the illustrated layer do not change the server contract.
