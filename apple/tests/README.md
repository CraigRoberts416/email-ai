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
- Durable scroll-read delivery across session changes, serial provider writes,
  failure rollback and replay after cold launch.
- Persisted display counts across same-day tab changes and cold starts, and
  safe invalidation when the day or time zone changes.
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

For an actual native layout/navigation check, launch a DEBUG build with
`-verifyFeedNavigation` on a Simulator whose cached feed has at least 20 cards.
The probe stages two existing unread cards as an in-memory arrival, moves to a
later card, invokes the same admission handler as the bubble, and checks the
resulting offset, ordered admission, unchanged unread state, and subsequent
movement down and back to top. It logs only booleans and does not modify Gmail
labels. This proves programmatic navigation through SwiftUI layout, not manual
scroll gesture recognition or a provider-delivered arrival. Release builds do
not contain the probe. Relaunch normally after the check.

## Send, source and discussion boundaries

`./apple/tests/run-send-lifecycle-tests.sh` compiles production send lifecycle and
local draft/discussion storage with the same controlled transport harness. It
uses a temporary storage directory and never touches account credentials or mail.

`./apple/tests/run-gmail-mime-tests.sh` compiles the production MIME builder and
validates the result with Python's independent MIME parser, including binary
attachments and header injection boundaries.

Run the source document policy check with:

```sh
swiftc apple/DecisionInbox/Services/EmailHTMLPolicy.swift apple/tests/EmailHTMLPolicyTests.swift -o /tmp/decision-inbox-email-policy-tests
/tmp/decision-inbox-email-policy-tests
```

This checks generated CSP, not runtime WebKit network traffic. Server discussion
history/scope checks run with `node --test server/discussionContext.test.js`.

## Actual WebKit remote-content boundary

Run `python3 apple/tests/run-email-webkit-tests.py` on macOS with a user session.
It compiles the production `EmailHTMLPolicy`, extracts the current WebKit
configuration, content rule and navigation delegate from `EmailBodyWeb.swift`,
and loads synthetic HTML in a hidden native `WKWebView`. A server bound only to
`127.0.0.1` records requests. The external-open API is replaced with a recorded
sink, so HTTP/mailto clicks never open a browser or mail client. Build files and
recorder are temporary; the compiled test content rule is removed on completion.

Verified on macOS 26.5.1, WebKit 21624.2.5.11.4:

- Zero HTTP requests before consent, including image/srcset/CSS/font/frame,
  script/preload, media, form and connection fixtures.
- Eight image/style/font requests after consent; no disallowed resource requests.
- Zero HTTP requests after consent is revoked on the same view.
- Sender JavaScript does not run; injected fetch/form/script-URL attempts are
  blocked. Automatic navigation actually reaches the delegate and is cancelled;
  deliberate HTTP/mailto links reach the external-open boundary instead.
- The data store is nonpersistent.

This verifies a real macOS WebKit network boundary. It does not measure rendering
performance or replace the separate iOS/device, VoiceOver and layout checks.

The send lifecycle runner also extracts the production `ComposeRecoveryState`
from `ComposeView.swift`. This checks explicit Activity and ordinary cached-draft
entry routes against the same recovery logic used by the editor: an unknown send
keeps its Check Sent gate, and an incomplete forward keeps its reload action even
when no transient error message survives reopening.
