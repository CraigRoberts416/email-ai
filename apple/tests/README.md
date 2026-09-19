# Native model checks

Run the feed integration harness from the repository root:

```sh
./apple/tests/run-feed-store-tests.sh
```

This macOS Swift executable compiles the **production** `FeedStore`, `APIClient`,
`FeedSession`, `FeedPaginationLifecycle`, and message/conversation models. It sends
fixture JSON through the real API decoder and uses controlled HTTP completions
and live-event delivery to exercise the store's asynchronous behavior.

The service doubles keep preferences, cache contents, badge writes, Gmail calls,
and live streams in memory. A registered `URLProtocol` intercepts every request;
unrecognized routes fail locally. No signed-in account, keychain, production
server, notification permission, or mailbox mutation is used.

Coverage includes:

- HTTP/live-event read confirmations in either order, duplicate confirmations,
  failed HTTP after successful live confirmation, failed reads and retries.
- Read cards retained during the visit and removed at the next session boundary.
- Cached cards, external reads beyond the first 200 IDs, complete and failed
  reconciliation batches, and counts for unloaded historical mail.
- Duplicate-only pages, overlapping old/new pagination generations, and globally
  chronological multi-account pages.
- Incomplete synchronization, missing cards, malformed response cards, and
  prevention of false completion.
- New-mail admission, duplicate live events, archived unread mail, Spam/Trash
  exclusions, and badges including connected accounts excluded from the feed.

These are store/service integration checks. They do not verify SwiftUI geometry,
scroll detection, navigation, APNs delivery, actual Gmail behavior, or device
performance. Those require the separate Simulator/device validation.

The other `*Tests.swift` files are focused executable checks for their named
production model/cache types; compile each with its corresponding source and
the fixtures declared in that test file.

Run `./apple/tests/run-notification-delegate-tests.sh` to exercise the production
notification delegate extension with platform doubles. Both callbacks enter
from a background queue; checks require main-thread completion, routing before
tap completion, and immediate foreground presentation before mailbox refresh.
