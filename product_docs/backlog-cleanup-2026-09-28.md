# Clear unread backlog

The user requested a control for clearing approximately 22,000 unread emails. This extends the inbox-zero contract in `Email App.md` §11.12 with deliberate bulk read status. It preserves mail, the stable feed session, the robot refresh artwork, and native navigation.

## Control

You → Feed → Clear unread backlog. Choose All unread or Before a date, select mailboxes, then Preview emails. A complete provider identity inventory supplies the exact count. A native confirmation is required before Mark N as read begins. The date cutoff is local midnight; All unread shares the first server snapshot cutoff across accounts. Archived unread mail is eligible; Spam and Trash are excluded. Messages arriving afterward remain unread.

Pause stops after the current request. Leaving or backgrounding also requests pause. Resume checks durable server state before proceeding. Finish here abandons remaining work with confirmation; confirmed batches stay read. Relaunch restores a receipt without restarting writes. Preview, Cancel, and changing selection have no Gmail write effects.

## Implementation

- `BacklogCleanup.swift` stores account/job references and approval in a device journal. `BacklogCleanupView.swift` uses shared settings, primary-button, typography, back-navigation and motion tokens.
- Authenticated `/feed/backlog` routes enumerate Gmail in pages of 500, then batch-remove only `UNREAD` from the frozen identities. The server stores the manifest and completed offset in PostgreSQL, scoped to the authenticated account. Job version checks recover responses lost after commit without repeating confirmed batches.
- The mailbox mirror preserves unrelated labels and newer Gmail revisions. FeedStore applies confirmed identities without removing current-session cards, invalidates counts and refreshes provider totals/badges. Completion is about the selected snapshot; it does not assert live inbox zero.
- A network failure pauses visibly. A Gmail request that succeeds immediately before a database failure may be retried as an unconfirmed batch; removing UNREAD is idempotent. Confirmed batches are not replayed. This is not a cross-provider atomic transaction or a bulk undo system.
- Unapproved per-account previews expire after 24 hours. A later selected account that has not started before expiry needs a new preview; already completed work stays read. The server does not continue work without client requests. Gmail quota failures pause rather than inventing progress.

## Verification

- 22,000-message synthetic inventory: 44 pages, exact identities, no preview writes, 44 bounded apply requests. New-arrival exclusion, date boundaries, expiry, ownership, zero matches, provider failure/recovery, SQL rollback and Gmail revision ordering were checked.
- Native model/transport suite: 204 checks passed, including multi-account cutoff, durable approval, pause/relaunch, lost-response recovery, account isolation, stable session positions and removal on the next session.
- Native Simulator: two focused UI tests passed, covering scope/date picker, preview, Cancel, confirmation, completion and Pause/Resume. Screenshots visually inspected. Tests used synthetic accounts and no live bulk read mutations.
- Existing full server suite passed 139 tests before the additional HTTP route test; the final eight focused backlog tests passed including authenticated HTTP routing.

## Figma

[Editable native backlog board](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=396-1880) includes selection, exact preview, paused progress and completed states with reusable controls and interaction notes. The existing native Feed settings screen also includes the entry. Counts/addresses in the board are synthetic; no private email content is copied.

Live deployment and TestFlight evidence are recorded separately when verified.
