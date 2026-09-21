# Margin Studio — production illustrations

September 20, 2026. The user explicitly requested completion of the illustrated signature layer and TestFlight distribution. This is production artwork, separate from the earlier tooling fixture.

The visual language is paper, editorial margins, a held place and a full stop. Rive draws; SwiftUI supplies truthful state, words, actions and accessibility. The selected moments are the freshness receipt, source-to-reading illustration and a rare closing mark. Alternative concepts requiring source citations or preserved remote browser sessions are not implied by these illustrations.

## Three authored artboards

| Artboard | App inputs | Where it appears |
| --- | --- | --- |
| Receipt | `phase`: 0 gesture/held, 1 working, 2 confirmed, 3 attention; `pull`: actual gesture 0–100; `active`: working motion permission | Pull refresh; compact and expanded unsubscribe Activity |
| Reading | `phase`: 0 original, 1 reading, 2 annotation, 3 recovery, 4 empty; `active`: working motion permission | Onboarding comparison, initial sync, failed mailbox load/connection, Saved and empty Activity |
| Closing | `phase`: 0 open ending, 1 one-shot close, 2 settled; `active`: motion permission | Verified cleared feed, once per local day and selected mailbox set |

Pull does not indicate network progress. Checking loops only move a small margin. Unknown and human-reported outcomes never select the confirmed pose. Pending arrivals reopen the completion mark. Returning to an already-shown completion uses a static composition.

`build_art.py` is editable vector/timing source; it writes editable `scene.rml`. `rive.yaml` is the CLI project. The shipping asset is `apple/DecisionInbox/Resources/Motion/margin-studio.riv`. It is 16,675 bytes and contains **zero scripts, fonts, images, audio or remote resources**. CLI signing is unnecessary for a script-free file, per the official CLI publishing documentation. It loads in the unmodified official Apple runtime; no tools-enabled runtime or script-verification override is used.

## Reproduce

```sh
python3 design/motion/margin-studio/build_art.py
python3 design/motion/margin-studio/verify.py
cp design/motion/margin-studio/build/margin-studio.riv apple/DecisionInbox/Resources/Motion/margin-studio.riv
```

Use Rive CLI 1.1.0 (`~/.rive/bin/rive`). The checker verifies compilation, inspection, four gesture poses, two working loops, motionless working poses, distinct outcomes, the saved empty state and the closing sequence's settled/re-entry behavior. It retains image/readback evidence and benchmark output in ignored `build/`.

Apple runtime **6.24.0** is pinned in the Xcode project and `Package.resolved`. `PaperIllustration` gives each mounted view its own artboard/state machine and shares only the file/worker. It drops the player off-screen, off-route or when backgrounded; static states pause after settling. It reads system Reduce Motion and draws a native static fallback without mounting Rive. Asset/render failures use that same fallback. No illustration handles taps or exposes duplicate accessibility content.

## Native verification

A DEBUG-only `-sampleMotion` route exercises the actual shipping `.riv`, runtime and native wrapper with synthetic inputs. It provides state controls, pull-distance slider, static composition and mount/unmount control. `-motionCycle` exercises rapid state changes and five repeated mount cycles. `-motionPhase=1` opens the working composition; `-motionReduced` tests the exact native static drawing used by Reduce Motion. The latter is a composition test, not a system-setting override.

The native probe passed **84 numeric/boolean state readbacks and release of 12 temporary Rive configurations**. It exercises interrupted phase changes and independent artboards. This does not claim that Instruments verified all GPU/worker allocations; the shared file/worker intentionally remains cached.

The actual native onboarding and Activity layouts were inspected. The production FeedStore suite passed **156 checks**. CLI rendering of the Reading loop over 240 frames reported mean 0.193 ms / p95 0.433 ms and no WASM page growth. Those are headless desktop measurements, not iPhone frame-time or battery results. Simulator Animation Hitches and Time Profiler attachment failed to find the app process, so there is no usable native performance trace.

Release status and final evidence are recorded in `product_docs/native-release-2609202100.md`. Physical-device haptics, battery, VoiceOver navigation and frame pacing remain device verification items; no new sound or haptic was added.
