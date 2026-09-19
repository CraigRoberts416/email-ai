# Gmail history and request budget

The full inventory visits every Gmail page, including read and archived mail;
Spam and Trash remain outside that inventory. The saved provider cursor advances
only after a page is persisted. An incomplete or failed generation never reports
complete history. Retrying a failed import has a minimum 60-second quiet period.

Metadata, original sources, history, count reads and startup backfills share a
per-account queue: at most four active transfers and 80 quota units per second.
Original-source reads and sender history take priority over background inventory;
unread count reads take highest priority and retain their caller's deadline.
Body transfer and JSON decoding remain inside the concurrency slot. The budget
uses the current 20-unit `messages.get` cost and leaves headroom below the
6,000-unit per-user minute quota. Older projects may have different quotas.
See Google's [quota table](https://developers.google.com/workspace/gmail/api/reference/quota).

Only identified rate-limit 403s, 429s and server 5xx errors retry automatically,
at most four attempts with exponential backoff and shared `Retry-After` delays.
Long delays return a retryable failure to the import rather than retrying early.
Policy/permission/daily-limit 403s fail immediately. Logs contain HTTP status and
allowlisted reason codes, never provider messages, mail contents or credentials.
A previous unexplained 403 alone does not establish its cause. See Google's
[error handling guidance](https://developers.google.com/workspace/gmail/api/guides/handle-errors).

Ordinary inventory can reuse known immutable sender/participant metadata, while
still accounting for every listed ID. Missing legacy fields and locally excluded
Spam/Trash rows are refreshed. Successful groups persist before the next group,
so a later failure does not discard their progress. After an expired Gmail
history checkpoint, a persisted recovery flag instead requires full metadata
revalidation to repair category labels too. Generation checks prevent a prior
in-flight import from clearing a newer recovery or overwriting its cursor.

Run `node --test server/*.test.js server/tests/*.test.js` from the repository root.
Tests use isolated transport doubles and local PostgreSQL-compatible fixtures;
they do not contact Gmail or a configured production database.
