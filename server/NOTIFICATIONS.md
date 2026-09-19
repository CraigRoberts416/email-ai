# Native mail notifications

The native app registers an APNs device token. The server sends it directly to
Apple over HTTP/2. Legacy Expo tokens still use the Expo transport.

Configure these server environment variables using the hosting provider's secret
settings, never committed files:

| Name | Value |
| --- | --- |
| `APNS_KEY_ID` | Identifier of an **APNs-enabled** Apple signing key |
| `APNS_TEAM_ID` | Apple developer team owning the app |
| `APNS_PRIVATE_KEY` | Contents of its `.p8` file; actual or escaped newlines work |
| `APNS_PRIVATE_KEY_PATH` | Alternative to `APNS_PRIVATE_KEY`: path to a secret file |
| `APNS_TOPIC` | `com.craigroberts.decisioninbox` |
| `APNS_ENVIRONMENT` | `production` for TestFlight/App Store; `sandbox` for development builds |

Production is the default environment. An App Store Connect upload key is not
automatically an APNs-enabled key. Missing configuration keeps delivery pending
and logs a configuration warning; it does not pretend that a push was sent.

Every arrival queues a possible alert. It becomes eligible only when interpretation
is done, `requiresAttention` is true, and the message remains unread. Sender and
subject come from the email. The message body is not copied into the notification.
Existing mail from before notification registration is excluded. Pending alerts
older than 24 hours are not replayed as new mail.

The badge is the sum of Gmail's authoritative `UNREAD.messagesUnread` counts for
every account sharing the device token, including accounts excluded from the feed.
It includes archived unread mail and excludes Spam and Trash. The server uses
Gmail's counter, rather than raw locally mirrored UNREAD label membership, which
also contains unread Spam and Trash. It is independent of loaded feed pages and
the model's attention decision. One unavailable account makes the total unknown;
the server then preserves the existing badge. A confirmed zero explicitly clears
it. Provider changes are checked on Gmail webhooks and the existing two-minute
reconciliation loop. Badge-only requests use Apple's `alert` push type without a
banner or sound, since the `background` push type does not permit a badge.

Provider count requests are shared with feed verification. Feed responses never
wait for the provider; notification delivery can await the shared refresh, with
a 15-second overall deadline. Mailbox changes invalidate prior samples even
when notifications are disabled. Interpretation completion can reuse a sample
less than 30 seconds old because it does not itself change unread membership.
Failed, expired, or invalidated samples never publish a zero or a partial badge.

The database stores pending delivery, a short claim lease, and successful sends.
Worker completion and reconciliation share this queue, so repeated arrivals do
not create repeated alerts. Provider failures retain the pending entry for retry.
APNs and operating-system delivery remain best effort; a successful provider
response is not proof that a device displayed the notification.

`POST /auth/push-token` registers the authenticated account. Before disconnecting
an account, call `DELETE /auth/push-token` while its credentials are available.
An optional `pushToken` request field prevents clearing a newer registration.
Detaching an account updates the remaining device total, including zero when the
last account is removed. The current account schema stores one device token per
account; registering that account on another device replaces its previous token.

Notification taps carry both `userId` and `messageId`. The native app buffers a
cold-launch tap until navigation is attached and opens cached content immediately.
For messages outside loaded feed pages, `GET /messages/:messageId/card` resolves
the card in the authenticated mailbox (including read/archived mail); if metadata
is missing locally, it fetches just that message from Gmail. This does not insert
historical mail into the unread feed or start interpretation. Deleted/unavailable
messages return an explicit failure so the app can offer retry feedback.

Run isolated verification with `node --test server/tests/*.test.js`. These tests
use generated test keys and mocked transports/stores, never real mailboxes. A
physical-device acceptance pass still needs foreground, background, terminated,
read/zero, multi-account, permission-denied, and notification-tap checks.

API contracts follow Apple's [token authentication](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns),
[request headers](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns),
and [background notification](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) documentation,
and Google's [label counters](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.labels).
