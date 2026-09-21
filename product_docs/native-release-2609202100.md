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

Implementation commit **`b355452`** is pushed to `main`. The final release archive passed and is retained in Xcode's normal Organizer location:

`~/Library/Developer/Xcode/Archives/2026-09-20/DecisionInbox 2026-09-20 21.00.xcarchive`

The upload attempt at 21:04 EDT stopped before transfer with **`exportArchive Failed to Use Accounts`**. Xcode's distribution log says no account with App Store Connect access was available for team `48X38356RX`. Computer control then reported that the Mac was locked and could not be automatically unlocked. The user has been asked to unlock it; retry the prepared archive afterward. **Build 2609202100 has not been uploaded or verified available in TestFlight.**

The earlier App Store Connect browser session also required sign-in and then reported a blocking extension panel. After unlocking, use the existing Xcode account to retry upload and confirm the processed build in the existing Internal group. Do not claim upload success as tester availability.

Local evidence: `/tmp/di-signature-archive-final.log`, `/tmp/di-upload-2609202100.log`; uploaded build number must remain `2609202100` unless Apple has actually accepted it. The prior backend `a6e9043` is already live; this release changes native UI/assets only and needs no new backend contract.

The uncompressed archived app is about 10.4 MiB versus 4.5 MiB for the previous build; most of the increase is the native runtime. This is not Apple's compressed TestFlight download size.
