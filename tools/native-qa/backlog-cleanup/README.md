# Unread backlog control verification

September 28, 2026. Implementation: `969228b`.

`selection.png`, `preview.png`, `paused.png` and `complete.png` are native Simulator UI-test attachments with synthetic accounts. The completion capture catches the numeric transition in flight. `figma.png` and `settings-figma.png` are visually checked exports of the editable native design board and settings entry.

Test artifacts on the authoring Mac:

- `/tmp/di-backlog-native.xcresult`: two control tests, zero failures, 46.592 seconds.
- `/tmp/di-backlog-feed-regression.xcresult`: two real-swipe/session regression tests, zero failures, 41.076 seconds.
- `/tmp/di-backlog-model-final.log`: 204 native production-model checks.
- `/tmp/di-backlog-server-all.log`: 139 server tests before the additional HTTP test.
- `/tmp/di-backlog-server-final.log`: eight final backlog tests, including HTTP authentication, 22K identity enumeration, provider failures, SQL rollback and revision ordering.

The signed-in Recovery Simulator also completed a live Gmail preview of 21,491 eligible unread emails. No bulk Gmail writes were approved or executed during that check. Its private mailbox screen is not retained in this repository.

See `product_docs/backlog-cleanup-2026-09-28.md` for the interaction and persistence contract.
