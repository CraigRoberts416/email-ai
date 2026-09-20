# Project context for agents

Read the relevant project docs before making product or implementation decisions. The current app is the native SwiftUI implementation in `apple/DecisionInbox`; the root Expo app and its README/CLAUDE guidance describe an older client. Use `product_docs/figma-audit-2026-09-19.md` to distinguish current native references from archived concepts.

For interaction and animation work, read `MOTION_AND_DELIGHT_SYSTEM.md` and the relevant native design tokens. Preserve native platform behavior and existing reduced-motion/haptic policies. Motion is the web animation layer; it is not a SwiftUI runtime. The installed `.agents/skills/motion` guidance concerns web work.

The app-wide review is in `product_docs/whole-app-experience-audit-2026-09-19.md`; six concept directions are in `product_docs/motion-concept-directions-2026-09-19.md`. Actual tool versions, setup limits and tests are in `MOTION_TOOLING.md`. Retained synthetic fixtures under `tools/motion-lab` are authoring/verification tools, not app dependencies.

Unsubscribe's current audit and unresolved decisions are in `product_docs/unsubscribe-experience-audit-2026-09-19.md`. After reviewing the app-wide audit, the user explicitly approved implementation with “ok do all of it.” Concrete interaction, recovery, accessibility and motion improvements are now authorized. Mutually exclusive concept alternatives are not instructions to layer every alternative into one UI. Preserve the calm native direction and document implementation choices and remaining limits in `product_docs/interaction-implementation-2026-09-19.md`. Do not conflate closing progress, canceling an attempt and reversing an external unsubscribe.

Teach through the work: ground explanations briefly in the docs, make tradeoffs intuitive, and leave product choices with the user unless a recommendation or decision is requested. Identify contradictions in older docs instead of silently choosing a new product promise.
