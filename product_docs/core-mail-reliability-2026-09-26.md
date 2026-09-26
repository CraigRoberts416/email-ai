# Core mail reliability — September 26, 2026

Craig reported that showing and marking email read still failed in TestFlight. The previous 2609261241 release's isolated checks were insufficient evidence for the real mailbox path. This follow-up preserves the stable-session contract; it adds no visual redesign.

## Reproduced failures and repairs

- A promotion image decoding during a native swipe resized its row. The feed's geometry protection cancelled the rest of that gesture, losing reads on other cards. The new real-touch regression failed before the repair and passed afterward. Images now hold their layout from touch-down through deceleration, applying their own proportions after the gesture ends.
- The production server repeatedly received Google `invalid_grant`. Its read endpoint converted that condition into generic HTTP 500, although retrying the same expired grant cannot repair it. Typed reconnect errors now produce HTTP 401; transient provider failures remain retryable.
- A cached feed HTTP 200 cleared a reconnect requirement established by a failed read. The production FeedStore regression failed before the fix. Cached mail can still load, while only successful registration restores the known connection state. Recorded reads remain durable and resume after reconnect.
- Strict queue priority allowed continuous body/history requests to starve background unread reconciliation. The fairness regression failed before the change. Waiting background work now gets service after five seconds; urgent counters keep priority, and quota/concurrency limits remain unchanged.

## Evidence and limits

- Production Render logs showed repeated expired-grant failures through 18:29 EDT, followed by unread-reconciliation timeouts. Matching OAuth client IDs ruled out client-ID mismatch. This is evidence of server failures, not proof that every iPhone symptom has the same cause.
- Read-only real mailbox audit: Gmail enumerated **22,901** unread identities including excluded folders; the database contained exactly the same set, with **0 missing and 0 stale IDs**. Gmail's eligible count and the database's eligible count both equalled **22,105**. The database held 277,861 total messages. These are point-in-time checks, not permanent mailbox totals.
- The saved unread reconciliation state was `error`; its last completed checkpoint was September 21. Matching totals alone did not override that failed checkpoint or assert completion.
- Server suite: **138 tests passed** (`node --test server/tests/*.test.js server/gmailSync.history.test.js`). Includes real user-store error classification, HTTP read-handler behavior, cancellation/disconnect regressions, queue fairness, and existing storage/count coverage.
- Production FeedStore integration: **169 checks passed**. The new check proves cached feed success cannot dismiss required reconnection, and the existing check proves reconnect delivers recorded reads.
- Native **FeedGestures** suite: **8 tests passed**, zero failures in 133.6 seconds, iOS 26.5. Result `/tmp/di-core-reliability-ui.xcresult`; image-arrival before/after results `/tmp/di-late-promo-baseline.xcresult` and `/tmp/di-late-promo-fixed.xcresult`.
- Native real-account sign-in is still pending in DecisionInbox-Recovery-QA. No claim is made yet for a full real-account Simulator swipe through Gmail, real arrival-bubble verification, or physical-device performance.

## Specification and rollout

Updated `Email App.md` section 11.12, `server/FEED.md`, and the existing Figma session/recovery annotations. No private mail content or contact photos were uploaded to Figma.

Server changes are commit `87c4795`; deployment and live verification are pending. Native archive/upload status will be recorded after verification.
