# Native build 1.0 (2610090850) — upload blocked

October 9, 2026. Implementation commit `5b1f32c616c94f42945f282bc3e5d90876ced3af`.

Changes and verification: [images, activity and backlog access](images-and-activity-2026-10-09.md). [Machine-readable release evidence](../tools/native-qa/images-and-activity/release-2610090850.json).

## Backend

Render reports commit `5b1f32c` **Live**, deployment `dep-db4dpq942hec73cf4s5g`, duration 1m29s. The body, image, signed-inline attachment and backlog job routes reject unauthenticated probes with 401. No schema migration was required. Full real-mail operation remains unverified in this run because the Recovery Simulator's Google grant has expired; reconnection was requested.

## Native

Release archive succeeded for `com.craigroberts.decisioninbox`, version 1.0, build 2610090850. Strict code-signature validation passed. No test bundles or DEBUG sample-feed flags are present. The production Rive asset remains unchanged at SHA-256 `ae690c2f817d3df4a4efce5eaeea8711aea78c5cd9e1695a3202cf7ff89d08a7`.

Archive: `/Users/craigroberts/Library/Developer/Xcode/Archives/2026-10-09/DecisionInbox 2026-10-09 08.50.xcarchive`.

**This build has not uploaded to Apple.** `xcodebuild -exportArchive` stopped at the account step with `Failed to Use Accounts`; the recovery message requires App Store Connect access for team `48X38356RX`. The App Store Connect web session is also signed out. Xcode's UI is blocked by an optional “Allow Codex to access Xcode?” prompt that did not respond to automated dismissal; the user was asked to dismiss it and reconnect their Apple Account in Xcode Settings → Accounts. No new Xcode access was granted.

Upload can resume from this archive once the Xcode account works. Local export options remain at `/tmp/di-oct9-export-options.plist`; distribution logs are under `/var/folders/fw/wfc9_d6d0jv_zq3kbb971m0m0000gp/T/DecisionInbox_2026-10-09_08-24-06.864.xcdistributionlogs`. Confirm Apple upload acceptance and TestFlight processing separately.

## Visual evidence

Retained synthetic Simulator captures show [Clear unread in Feed](../tools/native-qa/images-and-activity/feed-clear-unread.png), [the feed after the notice expires](../tools/native-qa/images-and-activity/feed-no-banner.png), [exact cleanup preview](../tools/native-qa/images-and-activity/backlog-preview.png), and [retained Activity history](../tools/native-qa/images-and-activity/activity-history.png). Both new UI tests were rerun solely to retain these missing screenshots; both passed. No private email contents were retained.
