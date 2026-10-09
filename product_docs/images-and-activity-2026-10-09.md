# Images, activity notices and a visible backlog control

October 9, 2026. Targeted improvements to the existing native app. The user explicitly chose automatic images in every opened email. This supersedes older default-blocked reader guidance; scripts and active content remain disabled.

## Changes

- Activity feedback dismisses after eight seconds, retaining the existing send Undo window. The store owns the deadline; changing tabs cannot restart it. Restored tasks stay in Activity without automatically opening the banner. Manual dismissal cancels the timer; older timers cannot dismiss newer notices.
- Feed exposes **Clear unread** beside its total, with a vertical fallback at larger text sizes. The existing All unread / Before a date, mailbox selection, exact preview, confirmation, Pause/Resume flow is reused. Preview does not change Gmail. Closing after processed batches begins a fresh feed session; preview/cancel preserves the current visit. The alternate You → Feed route remains.
- Opened HTML email loads images automatically. Privacy and data contains an opt-out; when off, **Load images** applies only to the current email. HTML draws incrementally. Scheme-relative image sources use HTTPS. Gmail CID parts become inline data or owner-signed attachment URLs with the image MIME type included in the signature.
- Feed images use shared downloads that survive view cancellation, off-main-thread disk I/O and ImageIO decoding, a decoded-image cache capped at 48 MiB / 128 entries, and existing seven-day disk snapshots. Decoding downsamples to 1,200 pixels. Three upcoming cards can warm their already-supplied picture URLs. Failed promotion images offer Retry image. The existing image/layout hold during scrolling is preserved.
- The server image proxy coalesces concurrent requests, retains at most 32 MiB / 128 images, and stops reading upstream images beyond 12 MiB. These are cache limits, not a claim about total app/server memory.

## Verification

- Production FeedStore integration: 209 checks passed.
- Interaction lifecycle: 83 checks passed; send/draft/discussion: 35 checks passed.
- Image pipeline: 11 checks passed for shared loads, viewport cancellation, downsampling, decoded/disk reuse, retry, clear and HTTPS. Production Swift task/cache/ImageIO code runs under a minimal macOS image wrapper; this is not an iPhone frame-rate benchmark.
- WebKit runtime: remote-off produced zero network requests, remote-on produced eight image/style/font requests, and switching off stopped requests again. Scripts, forms, frames, connections and automatic navigation remained blocked.
- Server tests: 44 root tests and 140 integration tests passed. Includes embedded images, bounded/coalesced downloads, existing 22K-backlog, ownership, read-state and persistence checks.
- FeedGestures Simulator scheme: 18 synthetic UI tests passed with zero failures (289.396 seconds). Covers new Feed cleanup entry/preview, notice expiry/tab return, cleanup confirmation/pause/resume, scroll-to-read, media arriving during a swipe, both refresh results, genuine arrivals from Earlier, historical-mail rejection and return-to-top. The opt-in live-mailbox test was skipped by the scheme.
- The signed-in Recovery Simulator launched with cached mail and no persistent activity notice, but reported expired Google access. Reconnection has been requested. Live image/backlog verification is therefore not yet claimed. No live bulk mark-read operation was performed.

## Figma

The existing editable [Feed screen](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=323-745) includes Clear unread. The [Privacy screen](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=339-952) includes automatic image loading. Activity, image-loading and backlog-entry annotations were updated in place. Existing native fonts, variables and toggle instances were reused; no private mail was copied. Rendered screens were inspected and sizing corrected.

Distribution evidence is recorded separately after backend deployment and Apple upload; successful tests or an archive do not establish TestFlight availability.
