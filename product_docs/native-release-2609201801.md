# Feed reliability release — 1.0 (2609201801)

September 20, 2026. Fixes the regressions reported from the prior TestFlight
build: repeated read emails, section counts repeatedly reverting to an ellipsis,
and the new-mail bubble failing to reveal its batch or return to the top.

Release source: `06a86fc` plus date-boundary correction `0af51f5`. Built from the
isolated `codex/feed-read-count-scroll` worktree based on production `3d89022`.
The separate app-interaction work in the main workspace is not part of this build.
No server changes are included.

## Changes

- Proven reads are synchronously recorded in a persistent store-owned queue.
  Navigation cancels only unfinished gesture evidence. Accepted reads continue
  serially, survive session changes, and replay after relaunch. Read failure
  retains retry information and restores the provisional countdown.
- Section display baselines survive same-day tab switches, app return and cold
  starts. A changed day or time zone requires fresh totals; an aggregate anchored
  before midnight cannot safely be split into new day sections. Provider totals
  still govern badges and verified completion.
- Bubble and endpoint admission share one handler: insert the pending batch,
  commit the updated layout, then issue a one-shot scroll to a permanent target
  outside the lazy rows. No retained scroll-position binding pins the viewport.
  The Feed tab now routes repeated selection through its binding instead of an
  `onChange` branch that could never observe equal old/new values.
- The countdown typography and numeric animation are preserved. Craig confirmed
  that the prior physical-device animation looked good; the new work fixes its
  data availability and delivery underneath it.

## Verification

Automated checks on the production models/services:

| Suite | Result |
|---|---:|
| FeedStore integration | 133 checks passed |
| API transport and decoding | 46 checks passed |
| Feed session | 18 checks passed |
| Pagination lifecycle | 13 checks passed |
| Scroll gesture evidence | Passed |
| Native Debug build | Passed |

The read-delivery tests cover immediate provisional progress, serial requests,
leaving before requests finish, failed-write rollback, persisted replay on cold
launch, and restored baseline counts without falsely claiming inbox zero.

Real-account Simulator checks on iPhone 17 Pro / iOS 26.4:

- A provider-verified 22,321 baseline appeared, stayed visible through later sync
  revalidation, and survived switching to People and returning to Feed.
- Two existing unread emails were opened during testing. Their read requests
  returned HTTP 200 and each reduced the displayed count by one. The final
  detail-return check confirmed the same card still present with read styling.
  Tab re-entry and app-background-return removed a confirmed-read card. A cold
  launch retained the updated display count. These are point-in-time counts,
  not a fixed claimed final mailbox total.
- A DEBUG-only navigation probe staged two existing cached unread emails as
  local pending arrivals, moved to a deep card, invoked the real bubble admission
  handler, then moved down and back to top again. All seven checks passed:
  depth reached, pending batch present, top reached, correct batch admitted,
  no programmatic reads, subsequent movement possible, and top reachable again.
  This probe makes no Gmail label changes and is excluded from Release builds.

The Simulator automation's physical drag/scroll input still produced no motion.
A manual swipe check was requested but has not been answered in this follow-up.
The layout probe establishes native programmatic navigation, not manual gesture
recognition or delivery of a newly received provider email. Physical-device
verification of the replacement build remains separate.

## Specification and Figma

Section 11.12 in `Email App.md` documents the updated persistence and navigation
contract. The existing [session board](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=341-780)
was updated in place (`341:1071`, `341:1085`, `341:1086`) and rendered again to
check layout. No private email content was copied into Figma or this record.

## Distribution

The final archive succeeded and upload completed at 18:05:23 Eastern. The
exported distribution payload has `CFBundleVersion=2609201801`,
`aps-environment=production`, `get-task-allow=false`, and signing team
`48X38356RX`. Its Release executable does not contain the DEBUG navigation probe.
Apple processing and Internal-group eligibility are being verified.

An earlier local archive, 2609201756, was superseded before upload. Its export
stopped before contacting Apple because a temporary export-options file was
missing. The corrected export configuration was used for 2609201801.
