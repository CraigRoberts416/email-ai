# Native release 1.0 (2609270943)

September 27, 2026. Supersedes uploaded build `2609270926` with the renderer correction found during final video review. Includes all bubble, read-delivery, refresh-admission and native status fixes described in [that release record](native-release-2609270926.md).

## Why another build was necessary

The wrapper treated every Rive error as fatal. A temporary Metal `noDrawable` callback during the pull overlay/inset transition discarded the player and selected static art for the remaining refresh. In a repeated native run, a logged callback at 09:39:13 matched the recorded frozen checking and arrival poses. Status-label assertions still passed, so those assertions alone were insufficient.

`PaperRenderStatus` now permits Rive to retry the next display tick for `noDrawable`. Asset-loading, missing-device and actual renderer failures retain the static fallback. Reduced Motion and route/background visibility policies are unchanged. No new gestures, motion assets, runtime versions or server changes are involved.

## Verification

The new native regression injects a temporary drawable miss through the real error handler and compares twelve robot-only image crops during the sample checking loop. Against the old fatal policy it failed with exactly one unique frame: `/tmp/di-drawable-baseline.xcresult`. The initial short-refresh version of this test missed the checking window because XCTest waited for UI idleness; the retained regression uses the existing held-checking fixture and does not alter production timing.

The earlier complete native suite passed 12 tests, FeedStore passed 178 checks, and arrival identity accounting passed 10 checks. The signed-in Gmail test passed bubble navigation, opening/confirmed read, scrolling, refresh and next-session removal. That real-mail test staged one existing unread message as an arrival in memory; it did not send new mail or establish physical-device performance.

The final renderer/refresh run passed **five native tests**, zero failures: `/tmp/di-drawable-final.xcresult`. This covers the same pixel-motion test against the correction, fast arrival and no-arrival refreshes, card-origin scrolling during Rive playback and scroll-past read/count confirmation during refresh. The retained recordings were visually reviewed: both knocks play; arrivals show falling envelopes before settling; no-arrival refreshes lower the stick without envelopes. Review contact sheets are `/tmp/di-arrival-motion-final.png` and `/tmp/di-no-arrival-motion-final.png`.

The existing Figma native recovery board was updated with the renderer rule and test coverage, then rendered and checked for clipping. Private Gmail captures remain local. The spec's stable-session and explicit-refresh behavior is unchanged from the preceding correction.

## Distribution

Release archive and signature checks passed for bundle `com.craigroberts.decisioninbox`, version **1.0 (2609270943)**. Archive: `~/Library/Developer/Xcode/Archives/2026-09-27/DecisionInbox 2026-09-27 09.43.xcarchive`. DEBUG sample/probe flags, including `-sampleDrawableMiss`, are absent from the executable. The bundled Rive asset is unchanged: SHA-256 `144d63f650f48438b469872c2efe82eaf406d1e4f58846fdab98543d563c1e4f`.

**Xcode Organizer confirmed successful upload of 1.0 (2609270943) at 09:46 EDT on September 27.** Its completion sheet identifies this exact build. App Store Connect's browser session remains signed out; the user has been asked to sign in so tester availability can be verified. Apple processing completion and Internal-group Testing status are not yet verified. Upload acceptance and availability to testers are separate checks.

The corrected Debug app was also installed on the signed-in `DecisionInbox-Recovery-QA` Simulator without uninstalling or clearing its account data, then launched normally without test flags. Backend deployment remains `31eef54`.
