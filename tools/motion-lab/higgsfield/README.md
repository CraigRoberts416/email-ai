# Higgsedit native motion proof

Verified 2026-09-19. This is a synthetic integration fixture, not approved app UI. No actual email, account action, paid generation or app code is involved.

The fixture is a save receipt with editable native text, rectangle and check path. Its entrance translates 22 pixels and fades in. The only variant is the entrance duration: **240 ms** versus **720 ms**. These visual choices are invented for the test.

## Results

| Check | Result |
| --- | --- |
| Native renderer | `@fable/headless` 0.14.0 via `/usr/local/bin/higgsedit` |
| Native CLI runtime | wrapper invokes `/opt/node22/bin/node` (22.22.1); generic sandbox `node` is 20.9.0 |
| Output | H.264, 640 × 360, 30 fps, 60 decoded frames, 2.000 seconds |
| Native frame renders | 0.00 s, 0.16 s, 1.00 s for each duration; no renderer diagnostics |
| Render report | CPU; no fallbacks; successful video export |
| Timing edit proof at 0.16 s | 44,948 of 230,400 pixels changed; mean absolute RGB difference 3.3865 |
| Same final state at 1.00 s | 0 changed pixels |
| Editable state | Both native projects, persisted document snapshots and authored JS retained in ZIP |
| Visual review | Browser review of comparison PNG confirmed legible text/check, coherent layout and slower variant visibly lower/fainter |
| Durability | PNG, comparison PNG, MP4 and editable ZIP PUT returned HTTP 200; all confirmed uploaded |

## Artifacts

- [2-second preview](https://d2ol7oe51mr4n9.cloudfront.net/user_323dKzyVF2jNYrzw32C6S1yxhSf/75a0bc11-027d-4349-a7d5-1046f33d5dd5.mp4)
- [Same timestamp, changed timing — left 240 ms, right 720 ms](https://d2ol7oe51mr4n9.cloudfront.net/user_323dKzyVF2jNYrzw32C6S1yxhSf/f9ff94eb-8a95-4988-9457-da13a8b978c1.png)
- [Settled frame](https://d2ol7oe51mr4n9.cloudfront.net/user_323dKzyVF2jNYrzw32C6S1yxhSf/ddbc1bc7-1859-441d-9c52-f9408d110cd1.png)
- [Editable projects, six PNG frames, preview and evidence ZIP](https://d2ol7oe51mr4n9.cloudfront.net/user_323dKzyVF2jNYrzw32C6S1yxhSf/914bc251-d2c3-4390-a399-39cf6f4f12c4.zip)
- Local authoring source: `receipt-proof.js`.

The ZIP is an editable file bundle, not a hosted editor URL. Extraction provides `output/baseline/project.json`, `output/retimed/project.json`, renders, `editable-document.json`, render reports, native inspect/check reports, ffprobe metadata, version evidence and pixel comparison metrics. The report's generic Node version is from the shell; Higgsedit's own wrapper uses the separate Node 22 binary stated above.

## Reproduce with the official hosted toolchain

1. Use Higgsfield `media_upload` to reserve durable outputs **before** starting the command that creates them.
2. In one `sandbox_exec` call: write the source; run `HIGGSEDIT_PROOF_DIR=/home/user/proof/output higgsedit build receipt-proof.js`; inspect/check both projects; run `ffprobe`; compare corresponding PNG pixels; package outputs; PUT them to the returned upload URLs.
3. Call `media_confirm` only after each PUT returns HTTP 200. The sandbox is ephemeral; do not leave the only copy there.

The authored source uses supplied native builders, `p.compose`, `p.frame`, `p.render` and `p.read`. It runs without React or a browser. `higgsedit doctor` passed all checks before creation. Exact script fields were checked against `/opt/fable/types/fable.d.ts`.

## Observed limits

- On this build, `--version` and `--capabilities` print generic help; do not interpret exit 0 as support. Version came from `/opt/fable/package.json`; capabilities from help/types and actual execution.
- `sandbox_exec` commands have a 16,000-character connector limit. Several long presigned URLs plus source exceeded that once; bundling the six rendered frames in ZIP kept the final command below the limit.
- ImageMagick `montage` aborted in the sandbox. FFmpeg `hstack` produced the verified comparison instead.
- This proves deterministic native media creation and retiming, not live SwiftUI/React Native interaction or native-app export integration. No Higgsedit runtime was added to the app.

Workflow references: [Video Editing skill](/Users/craigroberts/.codex/plugins/cache/openai-curated-remote/app-6a3293e129088191abf0875820e839da/2.0.0/skills/video-editing/SKILL.md), [Motion Craft skill](/Users/craigroberts/.codex/plugins/cache/openai-curated-remote/app-6a3293e129088191abf0875820e839da/2.0.0/skills/motion-craft/SKILL.md).
