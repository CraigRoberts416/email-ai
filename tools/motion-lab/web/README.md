# Isolated web motion lab

This is a small development tool using synthetic content. It is **not imported by the native SwiftUI app**, the root Expo client, or the server. No root package manifest/lockfile was changed. The lab has no mailbox API connection.

## Installed and verified on September 19, 2026

| Package | Exact installed version | Purpose |
|---|---|---|
| `motion` | 13.4.0 | React spring and layout animation |
| `motion-plus` → `@motionplus/core` | 2.12.0 | Actual premium `AnimateNumber` component |
| `gsap` | 3.15.0 | One explicit three-stage timeline |
| `react`, `react-dom` | 19.3.0 | Isolated browser component host |
| `vite` | 8.3.0 | Local server/build for this lab only |

Node 24.14.0 and npm 11.9.0 were used. Versions are pinned in this directory's package/lockfile.

## Run

From this directory, after dependencies are installed:

```sh
MOTION_TOKEN='' npm run dev
MOTION_TOKEN='' npm run smoke
MOTION_TOKEN='' npm run build
```

Open [the local lab](http://127.0.0.1:5189/). An empty value is sufficient for commands that do not download premium packages; it satisfies the token-free `.npmrc` variable without requiring a credential for runtime.

For a fresh authorized installation, supply `MOTION_TOKEN` to the install process and run `npm ci`. npm does not automatically load `.env` files. `python3 install-premium.py` is also available for a hidden terminal prompt; it installs the documented premium alias using a temporary npm cache, disables npm debug logs, redacts the captured output, and checks the local top-level files for the credential. It does not save the token. The script's `latest` install is an explicit dependency refresh, whereas `npm ci` reproduces the committed lockfile.

The task's initial credential was entered through hidden stdin and passed only to the npm child environment. No token was written into `.npmrc`, source, manifest, lockfile, README or a saved secret file. The temporary npm cache was deleted. A separate resolved-URL scan found no token-bearing package URLs. The existing repository ignores already cover `node_modules/` and `dist/`.

## What actually passed

| Check | Result / evidence |
|---|---|
| Official premium-registry authentication | Passed: installed `npm:@motionplus/core@2.12.0` through `https://api.motion.dev/npm/`; no legacy token-in-tarball URL. |
| Motion execution | Passed: `smoke.mjs` computed an intermediate spring value of 78.81695 and settled at 100. |
| React spring in Chrome | Passed: clicking Move spring produced the rendered `matrix(1, 0, 0, 1, 140, 0)` and Settled state. |
| React layout in Chrome | Passed: existing A/B/C items reversed to C/B/A and back; DOM order and settled positions were inspected. No frame-time/performance claim. |
| Premium import | Passed: actual `AnimateNumber` export imported from the installed `motion-plus/react` module. |
| Premium component in Chrome | Passed: rendered rolling-digit component; increment changed the component's accessible number and visible target (including 7→8 and later values). |
| GSAP execution | Passed: paused timeline midpoint/end assertions verified x=50, then x=100/turn=90; cleanup called. |
| GSAP browser timeline | Passed: actual translated/rotated intermediate DOM transform and Complete state observed; sequence returned to the start. |
| Reduced-motion preview | Passed: checkbox changes mode, premium component becomes static text, increment still works, GSAP finishes without spatial movement; identity transform verified. System preference hook is wired but changing the OS preference was not tested. |
| Build | Passed with warnings below. |
| Visual inspection | Passed for the full desktop page: controls, labels and all three sections visible without clipping. Small-screen/VoiceOver testing not performed. |
| Browser errors | No lab-source error in inspected warning/error records. Unrelated installed-extension warnings appeared; intermittent browser-control timeouts recovered using the supported browser API. |

`smoke.mjs` is a meaningful integration smoke check, not a claim of comprehensive tests. It also confirms the installed GSAP package contains DrawSVGPlugin, MorphSVGPlugin, MotionPathPlugin, SplitText and ScrollTrigger. Those plugins are **not imported or runtime-tested** in the demo, which uses only GSAP core.

## Compatibility and remaining verification

- Current Motion+ 2.12.0 declares `motion: ^12.25.0`, resolving a nested Motion 12.43.0 alongside the lab's current Motion 13.4.0. Their internal `framer-motion` packages are transitive dependencies; the application imports only `motion/react`, not the older public entry point. No unsupported override was forced. Shared contexts across the two versions are not established; the lab explicitly selects its static premium fallback for reduced motion.
- The build is 577.82 kB minified JavaScript / 189.49 kB gzip, including React, both Motion generations, Motion+ and GSAP. This is an isolated lab, **not a production bundle budget**. Runtime routing/code splitting and version alignment need a separate decision before any web production adoption.
- Vite/Rolldown reports module-level `use client` directives in dependencies and a chunk-size warning. This client-only lab builds and runs; SSR/RSC integration is not tested. Warnings were not silenced to claim a clean production build.
- No native integration, mobile device profiling, extended mount/unmount leak profiling, screen-reader session, MotionScore report, or saved/shared transition-editor test was performed. GSAP cleanup exists and the Node timeline is killed; that is not proof of a leak-free long session.
- **Motion package-token access and Motion MCP OAuth are separate.** This lab proves package access. It does not resolve or verify the parent task's hosted Motion/Motion+ MCP connection.
- Keep no account keys in client code. This lab's browser does not need the install credential. No paid upgrade, production deployment, or production secret configuration was performed.

## Official setup references

- [Motion+ registry installation and alias](https://motion.dev/docs/motion-plus-installation)
- [Motion React installation](https://motion.dev/docs/react-installation)
- [AnimateNumber API](https://motion.dev/docs/react-animate-number)
- [GSAP installation](https://gsap.com/docs/v3/Installation/) — the public package contains the plugins; the old private registry is unnecessary.
