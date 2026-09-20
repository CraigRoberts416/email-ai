// Synthetic, editable renderer proof. No app data or production integration.
// Run: HIGGSEDIT_PROOF_DIR=/absolute/output higgsedit build receipt-proof.js
import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

export default async ({ project, text, rect, path, frame }) => {
  const root = resolve(process.env.HIGGSEDIT_PROOF_DIR || "output");
  await mkdir(root, { recursive: true });
  const reports = { variants: [] };
  for (const [name, entranceSeconds] of [["baseline", 0.24], ["retimed", 0.72]]) {
    const p = await project({
      dir: resolve(root, name), size: "640x360", fps: 30, background: "#F7F7F4"
    });
    p.compose([
      text("MOTION LAB / SYNTHETIC", {
        x: 48, y: 28, width: 544, height: 24,
        fontFamily: "DM Sans", fontWeight: 700, fontSize: 12, color: "#777772"
      }),
      text("A small moment of closure.", {
        x: 48, y: 66, width: 544, height: 42,
        fontFamily: "DM Sans", fontWeight: 700, fontSize: 30, color: "#202020"
      }),
      text("Editable timing. Same final state.", {
        x: 48, y: 112, width: 544, height: 30,
        fontFamily: "DM Sans", fontWeight: 400, fontSize: 17, color: "#676762"
      }),
      frame({
        name: "save-receipt", x: 120, y: 173, width: 400, height: 104,
        layout: "none", origin: "top-left", background: "#FFFFFF", radius: 18,
        motion: { enter: {
          from: { y: 22, opacity: 0 }, duration: entranceSeconds, easing: "ease-out"
        }}
      }, [
        rect({ x: 22, y: 25, width: 54, height: 54, radius: 14, fill: "#222222" }),
        path({
          d: "M 3 13 L 10 20 L 25 4", x: 35, y: 38, width: 28, height: 28,
          stroke: { width: 3, color: "#FFFFFF", cap: "round" }
        }),
        text("Saved", {
          x: 96, y: 24, width: 274, height: 30,
          fontFamily: "DM Sans", fontWeight: 700, fontSize: 22, color: "#222222"
        }),
        text("Available in Saved.", {
          x: 96, y: 60, width: 274, height: 24,
          fontFamily: "DM Sans", fontWeight: 400, fontSize: 15, color: "#676762"
        })
      ]),
      text("Native text, vector paths and keyframes", {
        x: 48, y: 310, width: 544, height: 24,
        fontFamily: "DM Sans", fontWeight: 400, fontSize: 12, color: "#777772"
      })
    ], { at: 0, dur: 2, name: "Synthetic save receipt proof" });
    const frameReports = [];
    for (const [label, time] of [["early", 0], ["middle", 0.16], ["settled", 1]]) {
      frameReports.push(await p.frame(time, "renders/" + label + ".png"));
    }
    const renderReport = name === "baseline"
      ? await p.render("renders/proof.mp4", { concurrency: 1, shards: 1, depth: 8 })
      : null;
    const document = await p.read();
    reports.variants.push({ name, entranceSeconds, frameReports, renderReport });
    await writeFile(resolve(root, name, "editable-document.json"), JSON.stringify(document, null, 2));
  }
  await writeFile(resolve(root, "render-reports.json"), JSON.stringify(reports, null, 2));
  console.log(JSON.stringify(reports));
};
