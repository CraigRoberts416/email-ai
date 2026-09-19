# Inbox zero improvement review

September 18, 2026. Scope: improve the existing email app, preserving its card structure, monochrome palette, typography, and navigation. The user confirmed that scrolling past a post counts as seeing it and authorized a new TestFlight build after implementation.

## Current implementation

The checkout was updated to the current native SwiftUI application in `apple/DecisionInbox`, on `codex/inbox-zero-current`. The initial review inspected an older Expo checkout. Its implementation changes and JavaScript checks are historical observations, not evidence that the native app works or a description of its current typography tokens.

The native scope now also includes one shared profile structure for people and companies, feed-style posts in profiles, media/document grids, real personal avatars where available, and cached content before background refresh. Native startup inspection found that the store was created after the first render and caches were read inside asynchronous loading; the change constructs and hydrates the store before presentation. Network registration and reconciliation remain separate from cached display.

## Product contract

The existing spec already favored a finite feed and resolution. The change makes that endpoint concrete: user scrolling carries a post above the viewport, a confirmed read update clears it, and a completed feed stays clear. Viewing a post does not complete the request inside its email. Old posts are an explicit, optional destination after completion. The app icon counts provider-confirmed unread emails, which can differ from the number of loaded cards.

Detailed requirements and acceptance checks live in [Email App.md](./Email%20App.md), sections 2.10, 11.11–11.12, 12.9, and 13.11.1. The [zero-shot philosophy](./zero-shot-philosophy.md) now documents a narrow fallback exception for operational labels and recovery when runtime copy is unavailable; email interpretations remain generated from actual context.

## Skill coverage: first pass

The top-level skill files in `/Users/craigroberts/Documents/skills` were reviewed before the `DES SKILLS` pass. Review means the relevant instructions were applied to this scope, including recognizing where a specialist workflow does not fit.

| File | Identity | Application |
|---|---|---|
| `SKILL 2.md` | world-class-designer | Diagnose the unfinished feed loop before changing styling. |
| `SKILL(5).md` | world-class-product-designer | Separate seen/read state, requested actions, and completion. |
| `SKILL(6).md` | world-class-user-researcher | Keep observed code, user requirements, and predicted benefits distinct; no simulated user evidence. |
| `SKILL(7).md` | world-class-product-manager | Deliver a complete narrow loop; retain failure and re-entry behavior. |
| `SKILL(8).md` | world-class-content-designer | Make completion and recovery claims match known state; keep generation grounded. |
| `SKILL(10).md` | World-Class App Visual Designer | Preserve existing visual identity; refine hierarchy and controls. |
| `SKILL(2).md` | world-class-visual-designer | Improve secondary-text contrast and spacing without restyling. |
| `SKILL(20260822-152416).md` | world-class-app-visual-designer | Adapt headers and controls to content size and accessibility. |
| `SKILL(20260822-152652).md` | app-motion-designer | Respect reduced motion and avoid unnecessary movement. |
| `SKILL.md` and `world-class-illustrator-skill.zip` | world-class-illustrator | Assess clarity and restraint; no new illustration is needed. The archive was inspected in place. |
| `SKILL(1).md` | world-class-director-cinematographer | Cinematic production is outside scope; preserve purposeful emphasis. |
| `world_class_director_of_photography_SKILL.md` | world-class-director-of-photography | No photography production or replacement assets needed. |
| `world_class_pixar_style_work_SKILL.md` | World-Class Pixar-Style Work | No character or animation production needed. |
| `world-class-clothing-site-designer-SKILL.md` | world-class-clothing-site-designer | Apparel commerce workflow is outside this email task. |
| `world-class-fashion-designer-SKILL.md` | world-class-fashion-designer | Garment design workflow is outside scope. |
| `world-class-influencer-SKILL.md` | world-class-influencer | Creator growth and attention optimization are outside this completion-focused task. |
| `SKILL(20260822-223054).md` | personal-financial-advisor | Financial planning is outside scope; no financial data or advice involved. |

Some loose top-level skills link to reference folders that were not supplied alongside them. Their available core instructions were used; corresponding complete DES packages were reviewed in the second pass where present.

## Skill coverage: DES pass

All names below refer to package directories inside `/Users/craigroberts/Documents/skills/DES SKILLS`, each with its own `SKILL.md`.

| Package | Application |
|---|---|
| `world-class-product-designer` | State/recovery contracts and acceptance scenarios, using interaction and delivery references. |
| `world-class-content-design` | Distinguish true zero from unavailable data; remove canned prompt examples; use shared tone and precise action names. Interaction and AI content references applied. |
| `world-class-interaction-designer` | Require an actual forward scroll and a fully passed post; preserve position and retry failed read updates. Behavior-modeling reference applied. |
| `world-class-haptic-designer` | No repetitive per-card or completion haptics; keep repeated use calm. |
| `world-class-ios-creative-coder` | Keep native platform primitives and verify platform boundaries; production/inclusion reference applied. |
| `world-class-visual-designer` | Preserve the existing design system while refining hierarchy and consistency. |
| `world-class-color-designer` | Review secondary-text contrast. The legacy Expo pass measured `#686868` at 5.57:1 on white; native tokens require separate verification. |
| `world-class-typography-designer` | Retain existing fonts and improve legibility. Legacy leading changes do not establish native text behavior. |
| `world-class-layout-design` | Allow headers and metadata to grow/wrap; provide 44-pixel controls and centered icons. |
| `world-class-motion-designer` | Keep loading placeholders static when reduced motion is requested or its setting is unknown; avoid ornamental animation. |
| `world-class-illustration-designer` | Assess fit; no new artwork needed for a calm completion state. |
| `world-class-photography-design` | Keep sender avatars and fallbacks; avoid redundant screen-reader descriptions. No photo production required. |
| `world-class-creative-coder` | Preserve the current implementation stack and test behavior invariants. Engineering/accessibility references applied. |
| `world-class-web-creative-coder` | Keep the ordinary maintenance path; do not introduce a graphics stack. |
| `world-class-visual-creative-coder` | No generative visual system is needed for this task. |
| `world-class-experimental-coder` | Avoid speculative experiments; focus checks on concrete state transitions. |

## Evidence and limits

The product hypothesis is that a feed which stays clear will reinforce completion and reduce repeat scanning. This is an inference from the user's stated habit, not a demonstrated retention or usability result.

The source review identifies existing behavior and implementation requirements. The earlier 28-key UI-copy contract check applied only to the legacy Expo client. Native notification delivery, app-icon presentation, screen-reader behavior, cache-first presentation, and TestFlight distribution require their own verification. Do not infer those outcomes from this review record or legacy tests. Release verification is recorded by the implementation task.


## Native reference and design synchronization

Signed-in Mobbin references were inspected visually: [Instagram profile flow](https://mobbin.com/flows/75b6fe16-40a2-45c6-bd20-b11f1291219e) informed the compact identity, selected icon tab and close three-column media grid; [X profile flow](https://mobbin.com/flows/e4158f14-2675-4577-aef1-4e953b8b02d1) informed the banner/avatar seam and shared home/profile post vocabulary. Instagram currently uses taller thumbnails; the native implementation uses square tiles to keep photo and document lanes consistent. No visual assets were imported from either reference.

Contact photos are matched by email only after an explicit opt-in; the address book remains on the phone. Personal and company profiles share PostView; both media and documents use three square columns with 1pt gaps. A missing photo keeps initials or the existing avatar.

The existing [Figma file’s native implementation board](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=323-742) records these changes using native DM Sans/DM Mono styles, shared components and official iOS 26 chrome. Earlier explorations remain labeled separately; source code is the reference for implemented behavior.

Native backend verification includes 16 isolated APNs/badge tests. These establish signing, routing, aggregation, unknown-count handling and alert eligibility; they do not establish live APNs delivery. Physical-device notification and badge verification still requires configured provider credentials.

Figma verification: 12 editable native screen states and four completion/recovery/badge specimens were rendered and inspected. The original SenderProfile and document-grid components were updated, with one shared native PostView, bound Ink tokens and native text styles. The media grid deliberately shows image-loading placeholders, not invented received photos. The actual app-icon asset was reused for badge examples. A canvas constraint check found no board children outside the review section. These checks verify the design artifact, not physical-device behavior.
