# Sender history

`GET /sender-history?address=sender@example.com&kind=person|brand&limit=50&cursor=...`
authenticates one connected mailbox using the normal bearer token. The native
client aggregates responses across its connected mailboxes.

Companies combine addresses under the same canonical registrable domain,
including subdomains (`shipping@mail.amazon.co.uk` belongs to `amazon.co.uk`).
People and recognized shared email providers remain scoped to the exact sender
address. Unrelated corporate domains are not guessed to be the same company.

The provider query includes every date and both read/unread mail, including
archived mail, while excluding Spam and Trash. It enumerates all Gmail pages;
`resultSizeEstimate` is never used. Each candidate's actual From address is
checked against the scope, using existing metadata or fetching missing metadata,
so display-name matches cannot inflate the count. No AI call or body download is
required for enumeration.

The response is:

```
{ cards, nextCursor, totalCount, countComplete, syncState, sourcePendingCount,
  scope, scopeKey, countsAsOf }
```

- `cards` uses the same serializer as `/feed`.
- `totalCount` is null until every provider page and its required metadata have
  succeeded. `countComplete` is false for partial and failed enumeration.
- While `syncState` is `syncing`, clients poll the head and deduplicate cards.
  A null cursor in this state is not the end of history.
- Completed snapshots have stable opaque cursors. Cursor scope and account are
  validated; expired snapshots return HTTP 410 and require a fresh head request.
- `countsAsOf` identifies the enumeration time. Counts are verified as of that
  scan, not a claim that a mailbox cannot change afterward.

Concurrent opens of the same company/person share a job. A head snapshot is
reused for one minute; active pagination snapshots survive fifteen idle minutes.
Only IDs and dates are retained in snapshot memory; card metadata is read in
bounded pages. Failed enumeration is reported before a later head request can
retry. All cache state is process-local, so a server restart expires cursors.

Opening profile history never inserts old read mail into the unread feed, sends
historical notifications, or starts image generation. It does not by itself
claim that every attachment or embedded image has been inspected.

Requested card pages separately schedule source inspection, with four requests
running at a time. This fetches the original Gmail payload and attachment
metadata; it makes no AI calls and downloads no attachment files. Cards expose
`sourceInspected` and, for uninterpreted mail, an `originalText` excerpt (maximum
8,000 characters). Original text is never written into the AI quote or summary.
Profile inspection includes small files and more than eight attachments while
preserving the existing card extractor's defaults elsewhere.

`sourcePendingCount` counts uninspected cards on this response page. Clients may
poll the same page to merge source updates. Source failures remain unknown and
retry after thirty seconds; clients must offer a retry/status after bounded
polling. A completed email count does not prove that Media or Files is empty:
that statement requires all history pages loaded and all sources inspected.
Image candidates use the existing server-side validation, with a two-second
request timeout. Unavailable image hosts do not become confirmed empty media.

Provider references: [Gmail message listing](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/list),
[search and filtering](https://developers.google.com/workspace/gmail/api/guides/filtering).
