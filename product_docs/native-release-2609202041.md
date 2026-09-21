# App interaction release — 1.0 (2609202041)

September 20, 2026. The user explicitly requested TestFlight distribution. This release integrates the app-wide interaction work from `cd5489d` onto the current production source `52ea428`, retaining the feed-read/count/navigation corrections and the native People unread-conversation badge.

## Included and unfinished scope

The twenty implemented opportunities are recorded in [the implementation note](interaction-implementation-2026-09-19.md). This release adds native interaction/recovery work, persistent Activity and unsubscribe records, human handoff, durable saves/drafts, send recovery, discussion context, source-content consent and account/settings improvements.

**No production Rive animation or runtime is included.** The Rive state machine, Motion/Motion+ browser lab and editable AE receipt are separate authoring proofs. Illustrated signature interactions remain unfinished. The user was told this explicitly before upload; the tooling proof does not establish completion of the original creative brief.

## Integration checks

- Release archive succeeded for `com.craigroberts.decisioninbox`, version 1.0, build 2609202041, team 48X38356RX.
- 162 server tests passed.
- 156 production FeedStore checks passed, retaining later feed/badge tests and adding account-shutdown/read-queue integration checks.
- 83 interaction lifecycle checks passed.
- 35 send/draft/discussion checks passed.
- Conflict resolution retains the permanent non-lazy scroll target, store-owned recorded reads, People badge/polling, shared Activity and mailbox shutdown guards. Failed disconnect resumes eligible queued read work; successful removal clears that account’s queued intent.
- Previous synthetic Simulator screenshots, API/MIME/WebKit checks and physical-device limits remain in the implementation record. No live send, unsubscribe or disconnect was used as a test.

## Distribution

Archive prepared. App Store Connect upload, Apple processing, Internal-group eligibility and the matching Render backend deployment are being verified. No success is claimed here until the observations are recorded.
