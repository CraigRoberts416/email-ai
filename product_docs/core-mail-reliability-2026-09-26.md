# Core mail reliability — September 26, 2026

Craig reported that showing and marking email read still failed in TestFlight. The previous 2609261241 release's isolated checks were insufficient evidence for the real mailbox path. This follow-up preserves the stable-session contract; it adds no visual redesign.

## Reproduced failures and repairs

- A promotion image decoding during a native swipe resized its row. The feed's geometry protection cancelled the rest of that gesture, losing reads on other cards. The new real-touch regression failed before the repair and passed afterward. Images now hold their layout from touch-down through deceleration, applying their own proportions after the gesture ends.
- The production server repeatedly received Google `invalid_grant`. Its read endpoint converted that condition into generic HTTP 500, although retrying the same expired grant cannot repair it. Typed reconnect errors now produce HTTP 401; transient provider failures remain retryable.
- A cached feed HTTP 200 cleared a reconnect requirement established by a failed read. The production FeedStore regression failed before the fix. Cached mail can still load, while only successful registration restores the known connection state. Recorded reads remain durable and resume after reconnect.
- Strict queue priority allowed continuous body/history requests to starve background unread reconciliation. The fairness regression failed before the change. Waiting background work now gets service after five seconds; urgent counters keep priority, and quota/concurrency limits remain unchanged.
- A measured query plan read 8,739 disk pages because count aggregation opened full message rows to inspect labels. Eligible unread membership now has its own compact index; both section totals and raw unread diagnostics can use index-only scans within the same database snapshot. The index builds concurrently with existing reads/writes. A realistic regression includes 23k unread plus 50k read-history records; no response-size shortcut substitutes for query-plan verification. Earlier diagnostic elapsed times (including a 6,171 ms count and API timeouts) were contaminated: importing `db.js` also launched startup migrations. They are not valid normal-operation performance baselines. Final measurements must use a direct `pg.Pool`, never import the application's migration-running DB module.
- A corrected, migration-free probe still observed a slow 11,084 ms count followed by a 15-second feed timeout. Database evidence showed 40,994 dead row versions, a September 21 last autovacuum, disk reads and row-lock waits. Unread reconciliation was rewriting every unchanged unread row. It now applies only actual label differences; a production-SQL regression checks unchanged row versions remain untouched. Online `VACUUM (ANALYZE)` maintenance and final timing are recorded separately from mailbox read-state changes.

## Evidence and limits

The first live read check exposed a further failure absent from the original
fixtures: Gmail acknowledged removing UNREAD, but its immediately following
minimal GET still returned UNREAD. Repeating the request returned
`wasUnread: true` twice even though the provider total fell only once. A later
lookup settled to read. The server now retains Gmail's revision with confirmed
labels, ignores older metadata/history replay, and makes this retry return no
second decrement. A newer explicit mark-unread still takes effect. The stale
provider regression failed before the revision-aware correction.

- Production Render logs showed repeated expired-grant failures through 18:29 EDT, followed by unread-reconciliation timeouts. Matching OAuth client IDs ruled out client-ID mismatch. This is evidence of server failures, not proof that every iPhone symptom has the same cause.
- Read-only real mailbox audit: Gmail enumerated **22,901** unread identities including excluded folders; the database contained exactly the same set, with **0 missing and 0 stale IDs**. Gmail's eligible count and the database's eligible count both equalled **22,105**. The database held 277,861 total messages. These are point-in-time checks, not permanent mailbox totals.
- The saved unread reconciliation state was `error`; its last completed checkpoint was September 21. Matching totals alone did not override that failed checkpoint or assert completion.
- Final server suite including count-index and unchanged-row optimization: **142 tests passed** (`node --test server/tests/*.test.js server/gmailSync.history.test.js`; `/tmp/di-core-server-suite-noop.log`). Includes real user-store error classification, HTTP read-handler behavior, stale revision rejection, later explicit mark-unread, cancellation/disconnect regressions, queue fairness, and existing storage/count coverage. The 23k-unread/50k-read fixture verifies an index-only section scan, exact totals and bounded card payloads.
- Production FeedStore integration: **169 checks passed**. The new check proves cached feed success cannot dismiss required reconnection, and the existing check proves reconnect delivers recorded reads.
- Native **FeedGestures** suite: **8 tests passed**, zero failures in 133.6 seconds, iOS 26.5. Result `/tmp/di-core-reliability-ui.xcresult`; image-arrival before/after results `/tmp/di-late-promo-baseline.xcresult` and `/tmp/di-late-promo-fixed.xcresult`.
- Native real-account sign-in is still pending in DecisionInbox-Recovery-QA. No claim is made yet for a full real-account Simulator swipe through Gmail, real arrival-bubble verification, or physical-device performance.

## Specification and rollout

Updated `Email App.md` section 11.12, `server/FEED.md`, and the existing Figma session/recovery annotations. No private mail content or contact photos were uploaded to Figma.

Render deployed `87c4795`, `c5ebb3b`, `3cdf8fe` and finally **`31eef54`**, which is the verified live server. An early follow-up request timed out without changing the selected promotion; its migration-running diagnostic harness makes it unsuitable as ordinary request timing evidence. A staged real read then completed in 1,209 ms; Gmail and the mirror both reported read. Retrying completed in 166 ms with `wasUnread: false, readChanged: false`; other labels were preserved, and the eligible total decreased once from 22,104 to 22,103. A later settled lookup still reported read.

Unread reconciliation completed at **2026-09-26 22:59:50 UTC**. A subsequent `/feed/counts` returned `syncState: complete`, `countsComplete: true`, `knownStateComplete: true`, fresh provider total 22,103 and matching sections (UTC: 68 Today, 108 Yesterday, 21,927 Earlier).

After the final deployment, online `VACUUM (ANALYZE) messages` completed in **100,992 ms**. A first attempt had reached its 60-second limit. This is database row-version maintenance, not email deletion. The final migration-free live probe, using a direct `pg.Pool`, returned:

- First counts: HTTP 200, **332 ms**, database total 22,104; provider sample initially unavailable, correctly not complete.
- Normal **200-card feed**: HTTP 200, **365 ms**, 200 unique cards, all eligible unread. The read promotion was absent and explicitly included in `knownReadMessageIds`. Provider and database totals both 22,104; `countsComplete: true`, `syncState: complete`.
- Repeated counts: HTTP 200, **191 ms**, provider and database totals 22,104, complete.
- Direct database count: **113 ms**. The new index was both ready and valid.

The total changed between point-in-time checks; tests do not hard-code a permanent mailbox size. These timings are from the service's region, not iPhone network latency. They verify the live backend and fresh-feed removal, not a native swipe through Gmail. Figma's updated recovery/session annotations were visually checked; no implementation-only database controls were added to the product UI.

Native **1.0 (2609261850)** archived successfully and passed signature/build-number/DEBUG-exclusion checks; bundled Rive artwork is unchanged. Archive: `~/Library/Developer/Xcode/Archives/2026-09-26/DecisionInbox 2026-09-26 18.50.xcarchive`. It has **not been uploaded**. The Mac locked before Xcode distribution, and real-account Simulator Google sign-in remains incomplete; the user has been asked to unlock/sign in. A supported command-line upload attempt at 19:03 EDT also stopped before transfer with `exportArchive Failed to Use Accounts`; Xcode could not find an App Store Connect account for team `48X38356RX` (`/tmp/di-upload-2609261850.log`). These are outstanding checks, not passed checks.
