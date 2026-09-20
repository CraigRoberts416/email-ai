# After Effects native fixture — editable render verified

Verified September 20, 2026. The root task used the refreshed **direct After Effects MCP tools** to inspect a clean empty project, read the current catalog and official `ae-clean-rig` construction/validation guidance, save `before-fixture.aep`, and build the isolated synthetic fixture. This supersedes the earlier SDK-only failure; its history remains below.

This is an authoring integration proof, not production app UI or a native-app animation dependency. Palette, geometry, Arial typography and timing were invented for this fixture. No paid generation, mailbox operation or deployment was involved.

## Deliverables

- [Editable project](receipt-study.aep): the original 240 ms composition, a 720 ms timing duplicate and a separate content-edit duplicate.
- [Comparison preview](receipt-comparison.mp4): **240 ms on the left; 720 ms on the right**. Two seconds, 30 fps, 60 frames, H.264/yuv420p, 1280 × 360, no audio, 22,475 bytes. Encoded from native AE frames using FFmpeg 8.1.1, without intermediate-frame generation or retiming.
- `240-{start,middle,settled}.png` and `720-{start,middle,settled}.png`: native renders at **0, 0.12 and 1 second**.
- [Content edit](content-edit.png): “Saved” changed to “Saved for later” in a separate duplicate; the base composition remains unchanged.
- `executed-native-receipt.json`: the actual 26-operation creation source. `verification.json`: full creation/retiming responses and the inspected 720 ms layer tree. `post-render-verification.json`: independently checked structure, pixel differences, preview metadata and source/project SHA-256 hashes.
- `before-fixture.aep`: the separate empty-project backup made before structural changes.

The original `prepared-native-receipt.json` remains historical and marked unexecuted. Use the executed source and saved project for the completed fixture. The executed version explicitly keys opacity on child layers: AE parenting shares position but does not inherit opacity.

## What passed

| Check | Observed result |
| --- | --- |
| Native construction | 26 operations completed; two text layers, two shape layers, one solid background per comp |
| Geometry | One rounded card and one editable three-vertex check path; no masks or effects in the inspected tree |
| Motion | Five animated properties, two keys each; shared parent position plus separate opacity tracks |
| Retime | Every last key in the duplicate reads `0.72001953125` seconds, within 0.0001 s of the requested 720 ms |
| Interpolation | Every inspected in/out interpolation reports enum `6612`; the raw value is retained without guessing a symbolic name |
| Expressions | No expression operations authored and no expression errors reported in the returned tree; no expression-driven rig is claimed |
| Fonts | ArialMT and Arial-BoldMT present, no substitutions, zero missing fonts |
| Render | Root recorded 120 render operations with zero errors; independent decoding confirms two complete sequences of 60 valid 640 × 360 PNGs |
| Timing proof | At 0 s: **0 changed pixels**. At 0.12 s: **44,510 changed pixels**. At 1 s: **0 changed pixels** |
| Content edit | **823 changed pixels**, confined to the title region; settled native images visually reviewed and legible |
| Encoded preview | Metadata matches 30 fps / 60 frames / 2 s; an intermediate decoded comparison frame was visually reviewed |

The native frames have no sound. The short hold at the end makes the settled pose inspectable; it is not a seamless loop. This proof establishes editable composition, timing and rendered output, not a production design direction, broad editor reliability or iPhone performance.

## Reproduce the local checks

With Python 3, `ffmpeg` and `ffprobe` on PATH:

```sh
sh tools/motion-lab/after-effects/build-preview.sh
python3 tools/motion-lab/after-effects/verify-native-output.py
```

The 120 generated frames remain locally under `frames-240/` and `frames-720/` but are excluded from version control. The project, source, representative stills, preview and verification records are retained. To regenerate frame sequences, open the saved project through the official AE workflow, discover the current render schema and render each named comp at `frame / 30` for frames 0–59 to `frame-NNN.png`. Always inspect the current project first; these scripts themselves never communicate with AE or overwrite an open project.

Composition names:

- `DI_Motion_Lab_Receipt_240ms_20260919`
- `DI_Motion_Lab_Receipt_720ms_20260920`
- `DI_Motion_Lab_Receipt_Content_Check`

## Earlier failure retained for context

On September 19, `fnf-after-effects-mcp` 0.1.1 exposed its 197-operation catalog through an external MCP SDK diagnostic. One live read succeeded and reported AE `25.6x101`, but two subsequent sequential project reads timed out after 60,000 ms; the app displayed a second-script conflict. No fixture mutation, reset, override or force-kill followed those failures.

After direct tools appeared in the refreshed root session on September 20, fresh inspection succeeded and the separate backup/build/render proof above completed. The subagent's older tool context did not receive those new tools: its independent work here verifies the saved native results and packages the preview. The successful retry does not erase the earlier reliability issue.
