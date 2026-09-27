# 16-bit robot acting — September 27, 2026

The user requested finer 16-bit styling, a wooden stick, a full front-to-back-to-front head turn, feet/hip movement and surprise when mail falls. The subsequent no-mail request adds two small "nope" head shakes. The latest correction turns the torso, shoulders, pelvis and boots through front/three-quarter/side/back views with the helmet; translations and bends alone had left the torso facing forward. These retained artifacts use synthetic inputs only.

- `preview.html`: self-contained review of actual Rive frames, with working, arrivals and no-arrivals controls. The endings loop here for review; the app plays an ending once.
- `working.gif`: widened stance, hip/knee loading, rear-heel lift, full coordinated body/helmet turn and return.
- `arrivals.gif`: wide-eyed startle, sideways duck, upward peek and step back. Only phase 2 selects falling envelopes and the surprise sequence.
- `empty.gif`: lower stick, shake head left/right twice, then settle; no mail falls.
- `native-arrivals.png`, `native-no-mail.png`: actual native FeedGestures outcome captures.
- `native-reduced.png`: generated native static composition and the runtime probe's 116 passing bindings / 16 released hosts.
- `native-nope.png`: earlier native no-mail follow-up capture during the original head shake.
- `native-body-turn-arrivals.png`, `native-body-turn-empty.png`: latest native outcome captures with coordinated body orientation.
- `native-body-turn-reduced.png`: latest generated native static drawing; 116 bindings / 16 hosts passed.
- `body-turn-back.png`: actual Rive rear pose, with back shell, spine, vents, rear hip plates and heels.
- `rive-verification.json`: 18 passing art/state checks.
- `robot-benchmark.txt`: final Mailroom desktop benchmark; not physical-device performance evidence.
- `no-mail-benchmark.txt`: no-mail follow-up desktop benchmark; not physical-device performance evidence.

Head/body/surprise native regression run: `/tmp/di-16bit-acting-native.xcresult`; four tests passed, no failures, 43.393 seconds. The later head-shake revision passed the focused fast-no-arrival native test, zero failures, 10.702 seconds: `/tmp/di-robot-nope-native.xcresult`. No feed gestures, provider operations or outcome logic changed. The latest body-turn correction passed all 18 Rive checks and all three focused native tests, zero failures, in 33.023 seconds: `/tmp/di-robot-body-native.xcresult`. Current fifteen-pose asset SHA-256: `ae690c2f817d3df4a4efce5eaeea8711aea78c5cd9e1695a3202cf7ff89d08a7` (762,312 bytes). The generated static drawing now has outward-facing resting boots; the other three artboards are unchanged. Earlier benchmark files apply to the preceding art revisions.

This artwork is included in **1.0 (2609271718)**, successfully uploaded to Apple at 17:20 Eastern on September 27. `upload-2609271718.json` retains the Xcode upload event. Processing completion and tester availability still require verification; see [the release record](../../../../product_docs/native-release-2609271718.md).
