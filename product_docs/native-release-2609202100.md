# Illustrated motion release — 1.0 (2609202100)

September 20, 2026. The user explicitly requested the previously unfinished illustrated signature layer and TestFlight deployment. Work starts from `5bbb1b0`; the preceding release's interaction/recovery work and newer feed/People fixes are preserved.

## Delivered scope

- Three original, script-free production Rive artboards: **freshness receipt**, **source-to-reading paper**, and **closing mark**. Editable vector/timing source and verification live in [Margin Studio](../design/motion/margin-studio/README.md).
- Refresh follows real pull distance, working, result and failure. Onboarding's existing controls animate the synthetic source/annotation illustration. First sync, recovery, Saved and empty Activity use the same illustration family.
- Unsubscribe Activity maps real running, human-attention, unconfirmed and sender-confirmed states. It never visually confirms a request merely because it was sent or the user opened a browser.
- Completion closes only on verified zero with no pending arrivals, with a persisted once-per-local-day/selected-mailbox-set replay guard. Unverified endpoints remain open. Returning to an already-shown completion is static.
- Official Apple runtime 6.24.0, pinned through Swift Package Manager. The original artwork is 16,675 bytes. Reduced Motion and asset failures use native static drawing; words and controls stay native. Invisible/background illustrations release the player; non-looping poses pause after settling.

This delivers the selected illustrated layer in the approved calm native direction. It does not combine all six mutually exclusive signature alternatives, add a mascot/3D scene, fabricate source citations, or claim preserved remote-browser handoff.

## Validation

- Asset compile and scene inspection pass with no warnings; eleven behavior checks pass, including continuous pull poses, active/quiet states, truthful distinct outcomes and settled completion.
- Actual iOS runtime: 84 input-binding checks pass; all 12 temporary configurations are released. The native gallery completed interrupted state changes and five mount/unmount cycles.
- Existing production FeedStore integration: 156 checks pass.
- Native onboarding, refresh and Activity artwork/layout inspected in a dedicated synthetic Simulator. The static composition was rendered separately; a 375-point iPhone SE with maximum Dynamic Type showed stacked comparison controls and scrollable onboarding. [Retained synthetic evidence](../design/motion/margin-studio/evidence/).
- Release archive succeeded with the production asset and Rive runtime. Archive validation confirms version/build and absence of synthetic route flags. The Rive MIT license is bundled.
- No real sends, unsubscribes or account disconnects were used for testing.
- Headless desktop asset rendering: 0.193 ms mean / 0.433 ms p95 over 240 frames, no WASM-page growth. Native Instruments could not attach to the Simulator process; no physical-device performance or VoiceOver pass is claimed.

## Distribution

Release archive and TestFlight upload are in progress. App Store Connect browser verification is waiting for the user to finish sign-in and dismiss an extension panel that blocks automation. The prior backend `a6e9043` is already live; this release changes native UI/assets only and needs no new backend contract.
