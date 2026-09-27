# Native release 1.0 (2609270926)

September 27, 2026. Repairs the reported new-email bubble and skipped refresh outcomes without changing the stable-session product contract.

## Behavior

- Pending counts include only unique eligible mail absent from the current session. Repeated pending copies cannot announce an email already on screen.
- Bubble admission returns its actual batch. Navigation reveals the newest admitted card: the permanent top for the first date band, or the containing section for delayed Yesterday/Earlier mail. Targeting the whole section keeps the sticky date header above the sender. Feed retap still reaches the real top; subsequent scrolling remains free. Programmatic movement never marks mail read.
- Explicit refresh admits its newly fetched mail before reporting its outcome. Background arrivals still wait behind the bubble.
- Checking stays visible for 1.6 seconds from renderer readiness, enough for both authored knocks and recoil. Native success copy distinguishes **N NEW EMAILS** from **NO NEW EMAILS** and stays for 1.8 seconds. The arrival ending finishes before its player pauses. Fetched mail is usable immediately; the status presentation is nonblocking. Reduce Motion, failure recovery and visibility gating remain intact.
- This archive includes the earlier, previously unshipped native reliability repairs described in `core-mail-reliability-2026-09-26.md`. Server deployment remains `31eef54`; no server changes are needed for this follow-up.

## Verification

- Before the FeedView correction, the delayed-arrival bubble and fast-refresh checking tests both failed: `/tmp/di-arrival-refresh-baseline.xcresult`.
- Final synthetic **FeedGestures: 12 tests passed**, zero failures, iOS 26.5, 241.6 seconds: `/tmp/di-arrivals-release-regression.xcresult`. Includes both bubble destinations with actual opening of the announced email, free scrolling afterward, both fast-refresh outcomes, native scroll-past reads/counts, read removal on next visit, late image arrival during a swipe, refresh-time reading and completed-activity dismissal.
- Production FeedStore integration: **178 checks passed**, including duplicate pending identity rejection and explicit refresh across two accounts. Log `/tmp/di-arrival-store-final.log`.
- Arrival identity accounting: **10 checks passed**, including equal-total replacements, mailbox-qualified IDs, waiting mail and removed waiting mail.
- Synthetic landing captures were visually checked: the Yesterday header no longer covers the arrival's sender. An intermediate test used SwiftUI's unreliable combined-element `isHittable` flag; the final test verifies viewport position and delivers a real tap. Another intermediate run was disrupted while Simulator UI controls were being operated; it is not counted as evidence of a passed check.
- Signed-in **real Gmail native check passed**, zero failures in 26.3 seconds: `/tmp/di-real-arrival-refresh-final.xcresult`. It tapped the bubble, revealed/opened its announced email, observed provider-confirmed Read, swiped, returned to top, pulled to refresh, observed a successful outcome and verified the read email left the new session. Arrival timing was staged only in memory; all read and refresh requests used the actual account. This does not establish delivery latency for a newly sent email or physical-iPhone performance. The first opt-in test setup raced the session's automatic top request; the DEBUG setup now waits for that boundary before positioning the test. No private mailbox screenshots are uploaded to Figma or committed.

## Design and archive

Updated `Email App.md` §11.12, the mailroom state/timing contract, and the existing Figma session/recovery annotations. The Figma notes were visually checked for wrapping and clipping.

Archive: `~/Library/Developer/Xcode/Archives/2026-09-27/DecisionInbox 2026-09-27 09.26.xcarchive`. Release build/signature checks passed: bundle `com.craigroberts.decisioninbox`, version 1.0, build 2609270926. DEBUG sample/probe flags are absent from the executable. The existing Rive asset is unchanged, SHA-256 `144d63f650f48438b469872c2efe82eaf406d1e4f58846fdab98543d563c1e4f`.

Upload and tester availability are still pending at this checkpoint; an archive alone is not a deployed TestFlight build.
