# Native release — 1.0 (2609191136)

September 19, 2026. Native build processing is complete and the existing Internal group explicitly shows **Testing**. Final backend `dbef0ae` is live; its broader mailbox import has resumed and is measurably advancing. Complete archive reconciliation is still in progress. This record distinguishes verified surfaces from unfinished provider and device checks.

## Release artifacts

- Native changes: `0d1480e`; notification callback correction: `b43603d`; clear hero headers: source `20a4743`, carried into the isolated release checkout as `2c44b56`.
- Backend migration recovery: `6552be9`, verified **Deploy succeeded | Live** at 11:28:27 AM Eastern. Server startup and worker resumption appeared at 11:28:23 AM. Earlier port-scan warnings did not ultimately fail this deployment.
- Final backend `dbef0ae` is verified **Deploy succeeded | Live** at 11:50:51 AM Eastern; server startup and worker resumption appeared at 11:50:44 AM. This deployment showed normal repair progress and no startup deadlock/error.
- Build **2609191136** archived and uploaded successfully at 11:40:16 AM. The implementation task inspected the exported app: matching `CFBundleVersion`, `aps-environment=production`, and `get-task-allow=false`.
- [App Store Connect build](https://appstoreconnect.apple.com/teams/69a6de7f-4205-47e3-e053-5b8c7c11a4d1/apps/6812023896/testflight/ios/fafe55cf-cf4b-41c2-9606-35621c7f8467): upload **Complete**, general build-list status **Ready to Submit**. The separate **Internal → Builds** view explicitly shows **Testing**, iOS, expiring in 90 days, for **1.0 (2609191136)**. The group has one tester. This verifies internal testing eligibility; no installation is claimed from the invite count or group assignment.
- **2609191116 is superseded**: an actual Simulator notification tap exposed a main-thread delegate-completion crash. **2609191126 is superseded** by the clear-header refinement in 1136. Neither artifact was deleted or expired; existing groups/testers were not changed.

## Verification completed

The implementation task reported these runtime checks; they are separate from Figma rendering and isolated tests:

- Scrolled-past cards became read and retained their order in the active Feed session. Feed-tab return and pull-to-refresh removed read cards; opening and closing email detail preserved the session card.
- In a separate app-return check, the implementation task went to iOS Home and reopened through the app icon without switching tabs. A confirmed-read card was removed, its unread neighbors remained, and newly arrived emails appeared at the new session’s head. This verifies the app-background-return session boundary independently of tab switching.
- The **No more emails.** endpoint and old-posts opening passed in the isolated DEBUG `sampleFeedZero` fixture. Turning **See old posts** off persisted after reopening Settings; it was restored to On. Real Gmail was retained without bulk read changes. This does not claim a real mailbox reached zero.
- Real-account feed reconciliation matched the eligible provider total at a point in time. Simulator app-icon counts matched contemporaneous provider counts; these changed as mail arrived and was read, so no fixed final value is asserted. Badge scope includes archived unread across all connected accounts and excludes Spam/Trash.
- A real personal contact photo appeared in the tested People header/profile. Hayden’s thread opened immediately with original text, and the profile reconciled to **12 emails**, including October 2025 history. The final media retest on `dbef0ae` showed all **seven actual inline image thumbnails** rendered with **All emails loaded.**; an original image opened correctly in Quick Look. This does not establish every sender’s complete history.
- On the final backend, Amazon’s live profile displayed **5,633 EMAILS**, with accessibility explicitly identifying complete history. The 50 loaded cards combined eight distinct company sender addresses; the provider-verified total was not confused with that visible subset. The company logo, hero and clear profile header were checked. No addresses or email content were copied into this record.
- Amazon’s **Load older emails** control grew the cached page from 50 to 100 emails, expanded the combined sender-address set from eight to ten, and reached older dates while the verified total remained 5,633. The Docs lane correctly remained loading while source/history work was pending; it did not claim **No files.**. Opening People on the final backend showed the cached directory immediately.
- Shared native Back controls were checked on the dark hero and light settings surfaces. In 1136 Debug, original-email detail’s full-width frosted band was absent: the hero reached the sheet top behind separate native glass Back and More controls.
- After the delegate fix, warm/background and fully terminated/cold-launch notification taps opened an already-read email absent from the current Feed, exercising fallback routing. These were local Simulator push tests, not remote APNs delivery.
- Notification permission and badge remained On. The temporary test change to banner persistence was restored to the original **Temporary** setting, and the real Gmail Feed was left open.

Automated verification reported for the release and final recovery patch:

| Suite | Passing checks |
|---|---:|
| Backend | 125 |
| FeedStore | 116 |
| API | 46 |
| SenderHistory | 25 |
| Notification routing | 13 |
| Actual notification delegate | 10 |

These counts describe their respective suites. They do not substitute for manual animation, provider completeness, or physical-device checks.

## Figma and specification

[The full-file audit](./figma-audit-2026-09-19.md) records all 17 original pages’ historical disposition and the 53 current editable specimens. Canonical components and screens were rendered and inspected; the final source-loading edits were rendered again. Existing visual identity was preserved. Original-email posts, shared profiles, square media/doc grids, real-photo consent, stable Feed sessions, uppercase section countdowns, loading/retry states, badge scope and clear hero headers are documented in [the specification](./Email%20App.md).

Figma’s native glass is a static reference, and the file is not a fully wired prototype. No private email content or personal photos were copied into it.

## Backend recovery verification

The first combined deployment `0d1480e` failed on a startup migration deadlock. The follow-up `6552be9` split cross-table migrations and added bounded conflict retries; it completed startup. A read-only database snapshot afterward showed no blocking PIDs or index build in progress. That snapshot does not prove the cause of the earlier wait.

On the intermediate instance, full-history import advanced through six 500-message pages, then logged repeated **metadata fetch failed: 403** at 11:35–11:36 AM. Existing code did not preserve the provider’s reason. One explicitly authorized, read-only metadata probe later returned **HTTP 200**; no tokens, addresses, message IDs or content were output. That successful probe does not establish why the earlier request failed. The final backend adds safe provider-error detail and bounded pacing/retry. The Amazon profile total is verified independently of the broader mailbox import.

The recovery patch passed all 125 backend tests. Source commit `de6e7a5` was cherry-picked into the isolated release checkout as `dbef0ae` and pushed at approximately 11:49 AM. It adds paced Gmail reads, safe reason-coded failures, saved-page resume, and generation-conditional completion/pruning so an older import cannot overwrite a newer recovery request. Render Live status is verified.

The final instance logged **initial sync resumed at saved page** at 11:54:37 AM. Two bounded read-only database snapshots then counted **32,980** messages marked for the current import generation at 11:57:55 AM and **33,080** at 11:58:28 AM. Both showed `syncing` with a saved cursor present. This directly verifies 100 additional records accounted for during the observation window, without exposing identifiers, credentials or email content or changing data. It establishes active recovery, not exhaustive archive completion.

A completed, bounded Render failure-log search after these snapshots showed no matching failure entry from the final `mn4bb` instance. Its latest archive-failure result still belonged to the prior instance at 11:36:31 AM. This is scoped observation, not a guarantee that future provider requests cannot fail.

## Remaining acceptance checks

- Exhaustive broader archive completion; saved-page resume and active progress are verified. If a provider failure recurs, its safe reason-coded log should be checked without assuming the earlier 403’s cause.
- Installation of 1136 on a tester’s physical device; Internal-group **Testing** eligibility is verified.
- Physical-device remote APNs arrival, badge updates/clearing and notification navigation. Production credentials are configured and signing is verified; remote delivery remains unverified.
- The immediate manual section-countdown animation check is pending the user’s response. Automated state checks and static Figma transitions do not prove its perceived motion.
- Complete history/pagination across every sender and connected account, beyond the specific runtime paths listed above.

No external test email was sent. Native distribution and active backend recovery are verified within the scope above; the remaining acceptance checks are explicitly unresolved.
