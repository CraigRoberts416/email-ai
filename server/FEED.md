# Unread feed API

`GET /feed?limit=200&timeZone=America/New_York&sectionDate=2026-09-19T12:00:00Z`

Use the returned `nextCursor` as `cursor` on the next request. It is opaque and
account-specific. Omit it to start a new traversal. Limits are 1–200 (default
200). Timezone defaults to UTC; `sectionDate` defaults to the first request time.
Invalid options/cursors return HTTP 400.

Cards are unread messages across the complete historical mailbox, including
archived mail and all Gmail categories, excluding Spam and Trash. Pages order by
`internal_date DESC, message_id DESC` with a fixed bytewise ID tie-break. They
exclude records first imported after the initial page's snapshot. Reading or
removing an earlier card does not shift the next page. New arrivals and later
historical imports appear in a fresh traversal. A cursor is a traversal boundary,
not a frozen copy of read state: a message read before its later page is fetched
does not appear on that page.

Responses retain `cards` and provider `unreadCount`, and add:

- `nextCursor`: string or null; null means this snapshot's synced pages ended.
- `sections`: `{ today, yesterday, earlier }`, counted across **all** synced
  eligible unread mail, independent of loaded cards and cursor.
- `feedUnreadCount` and `syncedUnreadCount`: both equal the section-count sum.
- `allSyncedUnreadCount`: all synced unread messages, including Spam/Trash.
- `countsComplete`: true only after exhaustive unread reconciliation completed
  and `feedUnreadCount` equals the available Gmail UNREAD provider total. Both
  counters exclude Spam and Trash; raw `allSyncedUnreadCount` is diagnostic only.
- `syncState`: `pending`, `syncing`, `complete`, or `error`.
- `syncCompletedAt`: last successful reconciliation timestamp, or null.
- `countsAsOf`: timestamp of this database count snapshot.
- `providerCountAsOf`, `providerCountAgeMs`, `providerCountState`: age and state
  (`fresh`, `refreshing`, or `unavailable`) of provider verification. Samples
  are fresh for 30 seconds and must begin after the last completed import.
- `timeZone`, `sectionDate`: the section grouping anchor. The cursor retains it
  across midnight. Today includes the anchor's local day and future-dated mail;
  Yesterday is the previous local calendar day, respecting DST.

`GET /feed/counts?timeZone=...&sectionDate=...` returns the same count and sync
metadata without cards or a cursor. This allows live counts without replacing
the client's reading-session list. A confirmed local read can update a visible
counter immediately; use this endpoint to reconcile that counter.

Neither feed endpoint waits for Gmail's count request. A cold, expired, failed,
or invalidated provider sample returns `unreadCount: null` and
`countsComplete: false` alongside the cached cards and database sections. One
shared background request refreshes each account; the next client count poll
can verify the result. A stale zero never certifies completion. Refresh has a
15-second overall deadline, including OAuth token refresh, and a five-second
failure cooldown. Read operations and provider-change reconciliation invalidate
prior samples; late results from an invalidated request are discarded.

Both endpoints accept optional `knownMessageIds`, a comma-separated list of up
to 500 IDs from the requesting account. `knownReadMessageIds` contains only IDs
with an existing, currently read database row; an absent row is never assumed
read. `knownStateComplete` is true only when `countsComplete` is true. A client
can reconcile cached posts without treating omission from a bounded page as
proof of read state. More than 500 IDs or malformed IDs return HTTP 400.

`PATCH /messages/:messageId/read` returns
`{ success: true, wasUnread: boolean, readChanged: boolean }`. It reads Gmail's
current labels before removing UNREAD and updates the database from Gmail's
returned labels. Already-read mail succeeds with both flags false. The
`message-read` SSE event carries the same flags. Only a confirmed `wasUnread`
transition should decrement a live count; unknown flags require reconciliation.
Requests for the same account/message are serialized to avoid duplicate
transitions. Gmail failures do not emit a successful read event.

Completion requires `countsComplete`, zero eligible section totals, no pending
read failures, and no unread pages/arrivals awaiting the client's review.
An empty loaded page or `nextCursor: null` alone is not mailbox completion.
The app-icon badge keeps its existing Gmail total across connected accounts;
it includes archived unread mail and excludes Spam and Trash. It may remain
positive when an account excluded from the feed holds unread mail. Unknown or
incomplete totals must not be presented as exact mailbox totals.

## Reconciliation and verification

The server enumerates all Gmail UNREAD IDs, then unread Spam/Trash membership.
It fetches metadata only for missing or locally read IDs. It applies absent-ID
read reconciliation only after every page succeeds. Per-row label timestamps
prevent a slow import from undoing a more recent confirmed read. Interrupted
syncs remain incomplete and retry; active jobs are coalesced per account, with a
one-minute retry cooldown measured from completion or failure. A temporarily
unavailable provider count does not restart a completed import. The regular
periodic sweep also refreshes unread
membership independently of the history stream.

Run `node --test tests/*.test.js` from `server`. Feed tests execute production
SQL in an isolated in-memory PostgreSQL instance (PGlite, dev dependency), and
Gmail reconciliation tests use fake provider responses. They do not read account
data or modify a real database. Native behavior and deployment need separate
verification.
