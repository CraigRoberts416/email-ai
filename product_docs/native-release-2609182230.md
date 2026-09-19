# Native release 2609182230

September 18, 2026. App: Decision Inbox 1.0, `com.craigroberts.decisioninbox`.

## Delivered source and design

Implementation commit: `61f595c`, pushed to `origin/main`.

- Incoming posts clear after a forward scroll carries them above the viewport and the read update is confirmed. Layout changes alone do not clear posts. Failed updates retain posts with retry.
- Completion checks the provider unread count for included mailboxes and fetches the next unread batch before declaring inbox zero. Optional **See old posts** opens a separate history and can be disabled.
- People and company profiles share the main PostView. Photos and documents use three-column grids. Personal photos come from explicitly permitted device contacts.
- Feed/People caches restore before presentation. Opened email bodies cache locally for seven days; a failed refresh keeps the cached message visible. Cache clearing and account disconnect remove the relevant local copies.
- The greeting remains, with 64pt less space above it. Reading a request no longer produces a claim that nothing needs a response.
- Native APNs support delivers attention-only alerts and a provider-confirmed unread badge across connected accounts. Missing counts preserve the last badge.

[Figma implementation board](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=323-742): 12 editable native screens, four verification/recovery/badge specimens, shared PostView, updated profile/document components, and matching typography/tokens. The [skill review](./improvement-review.md) records both requested skill passes and exact Mobbin references.

## Verification

- Native ARM64 simulator build succeeded.
- Release archive succeeded, build `2609182230`, team `48X38356RX`.
- Xcode upload returned **Upload succeeded** and **EXPORT SUCCEEDED** at 22:34 EDT; Apple reported the uploaded package processing. TestFlight availability after processing has not been independently confirmed.
- 8 production scroll-state checks passed, including forward movement, reversal, cancellation, and layout-only movement.
- 16 production mail-cache checks passed, including expiry, corruption, Unicode/HTML, account/message isolation and disconnect cleanup.
- 16 isolated APNs/badge tests passed, including signing, production routing, zero/unknown counts, account aggregation, retry and alert eligibility.
- Additional isolated feed decoder/state checks passed. They are narrow service-double checks, not full-device end-to-end evidence.
- Sample UI verified explicit clearing through the final post, history entry/return without repopulating the feed, and shared person/company profile structure. Simulator touch-drag automation did not provide reliable gesture evidence; direct touch scrolling remains a TestFlight acceptance check.
- `git diff --check` and changed server JavaScript syntax checks passed.
- Following the push, the production server's new authenticated `DELETE /auth/push-token` endpoint changed from 404 to 401. This verifies the updated route is deployed without changing any account.

## Outstanding external setup

Closed-app native push delivery requires the APNs credentials documented in [server/NOTIFICATIONS.md](../server/NOTIFICATIONS.md). None were available in inspected local configuration, and Render/Apple Developer browser sessions require sign-in. Live device delivery and closed-app badge updates remain unverified until that configuration is completed. Foreground badge counting is implemented independently through Gmail.

Mobbin's official MCP is installed and OAuth-authenticated; the current live tool catalog requires a refresh to expose the newly configured server. Signed-in browser references were used for this design pass.
