# Feed recovery — September 26, 2026

Craig reported a persistent “Marked complete” banner, scroll passes that did not reduce unread counts, and a refresh error in the latest TestFlight. The session contract remains unchanged: proven reads update progress in place and leave on the next app/tab/refresh boundary.

## Repairs

- The compact Activity summary excludes user-reported completed unsubscribe runs. Marking the last pending run complete hides its banner; relaunch and replay of the same provider status preserve that dismissal. The full receipt remains available in Activity and never becomes provider-confirmed merely because the user completed it. Other pending work stays visible.
- A running refresh no longer disables later scroll-to-read gestures. Session resets, programmatic navigation and genuine geometry changes still cancel incomplete evidence. Actual passes continue into the durable read queue.
- Google refresh-token responses with HTTP 400 / `invalid_grant` now surface the existing reconnection path. One-time authorization-code failures, malformed responses and transient server errors remain retryable. The saved real-account Simulator grant returned this exact error in 0.28 seconds; no message body, token or account identity was included in diagnostic output. This establishes the Simulator failure, not the iPhone's exact failure.
- An unauthorized read exposes Reconnect and retains its recorded intent. Successful reconnection delivers those saved reads, preserves current-session cards, and reconnects the live arrival stream. The pull status also distinguishes Reconnect from Retry.

## Verification

- The completed-banner test failed before its fix and passes afterward.
- Production FeedStore integration: 168 checks passed, including reconnection recovery and banner persistence.
- Account connection policy: 18 checks passed, including expired grants, transient errors and authorization-code isolation.
- Full native Simulator test build passed for arm64 and x86_64.
- Native touch suite on iOS 26.5: all six checks passed. The same refresh-read check failed against the older binary and passed against the correction (`/tmp/di-260926-refresh-before.xcresult`, `/tmp/di-260926-recovery-ui.xcresult`).
- Three strengthened native checks passed: visible section count decreases plus read-card removal next session; count/read updates during held refresh; completed banner dismissal with the honest receipt retained in Activity (`/tmp/di-260926-count-banner-ui.xcresult`).
- Final combined recovery + robot implementation: all seven native touch tests passed on iOS 26.5, zero failures in 111.6 seconds (`/tmp/di-260926-combined-ui-final.xcresult`). Retained captures prove the reduced count/read state during robot refresh and the completed Activity receipt.
- Live-account recovery remains pending Google sign-in. The cached real feed and explicit Reconnect state were verified; authenticated refresh/read confirmation is not claimed. Distribution is recorded separately in `native-release-2609261241.md`.

Simulator initially stalled before app launch on both iOS runtimes, including a fresh device. After the other task stopped its QA device, shutting down the simulators and restarting Simulator.app, CoreSimulatorService and SimulatorTrampoline recovered native launches. Account storage was preserved. Later combined runs also stalled before runner launch. Restarting the Simulator launch services and using one QA device at a time recovered the final seven-test suite. This restart closed the pending Google login; the live-account flow was reopened afterward. Infrastructure startup failures were not counted as app test failures.

## Design and release coordination

The product spec and existing [Figma session notes](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=341-780), supporting receipt note, and recovery-board annotation were updated. Changes are behavior annotations, without a new visual direction or private email content.

The work began in `codex/feed-recovery-isolated-260926`, based on `7f290ec`. Animation commit `ffee594` was integrated as `01d5135`; merge `e2a57fa` reconciles both histories in the original checkout with the same tested tree. Superseded early local edits are preserved in a named stash and `/tmp/di-original-owned-recovery.patch`. Model, native UI, live-account and physical-device evidence remain separate.

The [native verification board](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=380-1879) now includes actual combined-build synthetic captures and recovery/arrival-state notes. Both placeholders were cleared and the complete board was visually checked for layout/clipping. No private mail or contact images were uploaded.
