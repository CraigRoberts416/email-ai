# Core mail reliability evidence

Synthetic native captures from the eight-test FeedGestures run on iOS 26.5:

- `read-retained.png`: read styling and reduced count, card retained until the next session.
- `read-during-refresh.png`: read/count updates while illustrated refresh continues.
- `verification.json`: test counts and aggregate real-mail diagnostics. No message contents, IDs, credentials or contact images are retained.

The image-arrival regression itself asserts read state after one actual pan and removal on the next tab visit. It failed in `/tmp/di-late-promo-baseline.xcresult` and passed in `/tmp/di-late-promo-fixed.xcresult`; the complete passing suite is `/tmp/di-core-reliability-ui.xcresult`.

The first real Gmail probe exposed provider lookup lag and duplicate decrement reporting; it is recorded as a failure, not a pass. Follow-up live results and distribution status belong in `product_docs/core-mail-reliability-2026-09-26.md`.
