# App interaction release — 1.0 (2609202041)

September 20, 2026. The user explicitly requested TestFlight distribution. This release integrates the app-wide interaction work from `cd5489d` onto the current production source `52ea428`, retaining the feed-read/count/navigation corrections and the native People unread-conversation badge.

## Included and unfinished scope

The twenty implemented opportunities are recorded in [the implementation note](interaction-implementation-2026-09-19.md). This release adds native interaction/recovery work, persistent Activity and unsubscribe records, human handoff, durable saves/drafts, send recovery, discussion context, source-content consent and account/settings improvements.

**No production Rive animation or runtime is included.** The Rive state machine, Motion/Motion+ browser lab and editable AE receipt are separate authoring proofs. Illustrated signature interactions remain unfinished. The user was told this explicitly before upload; the tooling proof does not establish completion of the original creative brief.

## Integration checks

- Release archive succeeded for `com.craigroberts.decisioninbox`, version 1.0, build 2609202041, team 48X38356RX.
- The exported, signed upload payload has `aps-environment=production` and `get-task-allow=false`; the Release executable contains none of the six synthetic Simulator launch flags.
- 162 server tests passed.
- 156 production FeedStore checks passed, retaining later feed/badge tests and adding account-shutdown/read-queue integration checks.
- 83 interaction lifecycle checks passed.
- 35 send/draft/discussion checks passed.
- Conflict resolution retains the permanent non-lazy scroll target, store-owned recorded reads, People badge/polling, shared Activity and mailbox shutdown guards. Failed disconnect resumes eligible queued read work; successful removal clears that account’s queued intent.
- Previous synthetic Simulator screenshots, API/MIME/WebKit checks and physical-device limits remain in the implementation record. No live send, unsubscribe or disconnect was used as a test.

## Distribution

- Integrated implementation commit: `ea8043b`. Release preparation commit: `a6e9043`, pushed to `main` without overwriting the newer feed and People work.
- Apple accepted build **1.0 (2609202041)** at 20:46 EDT on September 20. Xcode reported `Upload succeeded` and `EXPORT SUCCEEDED`; the package had entered processing. Local evidence: `/tmp/di-upload-2609202041.log` and `/tmp/decisioninbox-2609202041.xcarchive`.
- [Matching Render deployment](https://dashboard.render.com/web/srv-d6uoc2juibrs73aamoh0/deploys/dep-dao7rv68bjmc73b4q0n0) of `a6e9043` reported **Deploy succeeded | Live** at 20:47 EDT. Startup completed on port 10000. A read-only, unauthenticated request to the new `/unsubscribe/runs` endpoint returned its expected HTTP 401 JSON response, confirming the route is present without invoking an unsubscribe.
- Apple processing completion and availability in the existing Internal TestFlight group are **not yet verified**. App Store Connect displayed a fresh Apple sign-in when opening the iOS build list. The user has been asked to sign in in Chrome; upload success is not being represented as tester availability.

The native upload and backend deployment are complete. Remaining distribution work is to verify Apple's processed build and its assignment to the existing Internal group after browser sign-in. No real mailbox send, unsubscribe or disconnect was used to validate the release.
