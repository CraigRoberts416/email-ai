# Native release 1.0 (2609271718)

September 27, 2026. The user explicitly requested shipping the completed robot animation to TestFlight after reviewing the body-turn correction. Implementation commit: `10933bf` on `codex/mailroom-robot-260926`. This carries forward the feed/history fixes from release 2609271244 and changes the refresh illustration only.

## Included artwork

- Sixteen-bit pixel styling retains the supplied round-helmet robot, pale eyes and compact blue armor. A crooked wooden stick has bark knots, a trimmed twig and a cut end.
- Front, three-quarter, side and back drawings turn shoulders, torso, pelvis and boots with the helmet. Rear armor and heel plates replace the front chest and toe caps during the strike.
- New arrivals trigger widened eyes, a sideways duck, an upward peek and a return to rest. Successful refresh without arrivals lowers the stick, gives two small “nope” shakes and releases no envelopes.
- The stick still contacts the phone edge; there is no drawn ceiling. Native status/actions, phase timing, refresh data rules, gestures and reduced-motion behavior retain their existing contracts. The static native artwork is generated from the same resting poses.

## Verification

The final bundled asset passed all **18 Rive checks**. Compilation reported zero errors or warnings. Receipt, Reading and Closing artboard XML is unchanged. The script-free asset is **762,312 bytes**, SHA-256 `ae690c2f817d3df4a4efce5eaeea8711aea78c5cd9e1695a3202cf7ff89d08a7`; Rive Apple remains pinned to 6.24.0.

The three focused native tests passed with zero failures in **33.023 seconds**: fast arrivals, fast no-arrivals and continued pixel animation after a temporary drawable miss. Result: `/tmp/di-robot-body-native.xcresult`. Both outcome captures and the native static composition were visually inspected. The native runtime probe passed **116 bindings and release of 16 hosts**. These are synthetic Simulator checks, not a new physical-device performance claim. [Retained artwork and evidence](../tools/motion-lab/native-qa/mailroom-16bit/README.md).

## Distribution

The Release archive succeeded. Bundle identifier, version/build, strict code signature, Rive asset checksum and bundled runtime license were verified. DEBUG fixture flags and UI-test bundles are absent. **Xcode recorded a successful upload to Apple at 17:20:24 Eastern**, with no upload errors or warnings. Its archive metadata and distribution log identify build **2609271718**. [Upload receipt](../tools/motion-lab/native-qa/mailroom-16bit/upload-2609271718.json). Archive: `~/Library/Developer/Xcode/Archives/2026-09-27/DecisionInbox 2026-09-27 17.18.xcarchive`. The native-only release requires no backend deployment.

Apple processing completion and Internal-group availability are not yet verified: App Store Connect is signed out, and the Mac locked after upload. The user has been asked to unlock it and sign in. No external beta review or public App Store release was submitted.
