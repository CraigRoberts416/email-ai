# Native release 1.0 (2609271244)

September 27, 2026. The user's iPhone recording showed **5 NEW** taking the feed to a three-day-old email under EARLIER. The user confirmed that genuine arrivals should still produce a bubble while reading any section and take the reader to the top.

## Correction

The previous change repaired navigation to the pending batch but accepted the wrong meaning of “new”: a newly discovered identity could be historical mail. HTTP reconciliation, page recovery and live message-added events can all discover older mail. The earlier spec/test that deliberately navigated to Yesterday/Earlier is superseded by this correction.

- A mailbox's opening snapshot supplies its arrival boundary. Only unique eligible mail newer than that mailbox's opening head and in the session's TODAY band qualifies for the bubble. The day band stays anchored across midnight; mail newly arriving after midnight still belongs to this active TODAY band. A mailbox's head is independent of other accounts. With no head yet, the session's start time is the conservative boundary.
- Historical discoveries remain eligible unread mail. Normal pages append below the existing cards. Recovered history that would need insertion before already-visible cards waits for a session boundary. At the end of loaded mail, **Older emails synced. / Refresh to include them** preserves access without claiming everything is already displayed.
- A mixed pending batch counts and admits genuine arrivals only. Tapping the bubble always targets the permanent feed top, including when the reader was in EARLIER. Programmatic navigation still creates no read evidence.
- Explicit refresh also admits recovered history in date order and preserves cards read while its request was running. Its arrival-art/count calculation uses the boundary captured before the refresh reset; historical discovery does not trigger falling envelopes or NEW copy.
- The current spec and Figma arrival/recovery annotations are updated. No native gesture recognizer, motion asset, dependency or server behavior changes.

## Verification and distribution

FeedStore integration: **189 checks passed**. Includes old mail arriving through live events, today's recovered gaps, mixed batches, stable current cards, next-session history inclusion and explicit refresh recovery. Production session/date logic: **24 checks passed**, including independent mailbox boundaries, midnight and keeping the boundary from moving backward when read cards leave. Both suites were rerun after that final boundary adjustment.

Five native touch tests passed with zero failures in 78.8 seconds: `/tmp/di-history-bubble-final.xcresult`. They cover the normal arrival bubble, a genuine arrival tapped from Earlier with historical mail waiting, old-history recovery with no NEW bubble, and both fast-refresh outcomes. The mixed-batch test opens the announced email after navigation and confirms subsequent scrolling remains free. The landing capture was inspected: it shows the actual arrival under TODAY at the feed top. The initial test build caught an immutable fixture-ID assignment; that DEBUG fixture construction was corrected before the successful run.

After the final read-head boundary adjustment, both history/arrival touch cases passed again with zero failures in 35.9 seconds: `/tmp/di-history-release-native.xcresult`. The final Debug build was installed on the authenticated Recovery-QA Simulator without clearing account data and launched normally. This follow-up used synthetic mail for controlled history/arrival timing; it does not claim a newly delivered real Gmail event or a physical-iPhone pass.

Xcode confirmed **DecisionInbox 1.0 (2609271244) uploaded** at 12:50 PM Eastern. The final archive is `~/Library/Developer/Xcode/Archives/2026-09-27/DecisionInbox 2026-09-27 12.44.xcarchive`; its bundle ID, build number and strict code signature were verified, and DEBUG staging flags are absent from the executable. The bundled Rive asset is unchanged. App Store Connect processing completed, and the Internal group lists this exact build as **Testing** with 90 days remaining. Its one tester also reports **Installed 1.0 (2609271244)**. What to Test notes were saved. Apple build ID: `5a1b1a7d-7d92-4330-90da-e2726db56247`. Backend deployment remains `31eef54`; this is a native-only release. The source recording and private mailbox content remain local. Figma's updated contract and recovery board were rendered and visually checked.
