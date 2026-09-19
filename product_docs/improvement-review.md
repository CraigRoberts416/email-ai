# Inbox zero improvement review

Updated September 19, 2026. Scope: improve the existing email app, preserving its card structure, monochrome palette, typography, and navigation. The user confirmed that scrolling past a post counts as seeing it and authorized a new TestFlight build after implementation.

## Current implementation

Final native build **2609191136** is explicitly **Testing** in the existing TestFlight Internal group. Backend `dbef0ae` is Live and has resumed its saved historical-import cursor with measured progress; exhaustive archive completion remains in progress. The [release verification record](./native-release-2609191136.md) contains the final evidence and remaining physical-device/manual checks. Earlier audit entries below describe intermediate states.

The checkout was updated to the current native SwiftUI application in `apple/DecisionInbox`, on `codex/inbox-zero-current`. The initial review inspected an older Expo checkout. Its implementation changes and JavaScript checks are historical observations, not evidence that the native app works or a description of its current typography tokens.

The native scope now also includes one shared profile structure for people and companies, feed-style posts in profiles, media/document grids, real personal avatars where available, and cached content before background refresh. Native startup inspection found that the store was created after the first render and caches were read inside asynchronous loading; the change constructs and hydrates the store before presentation. Network registration and reconciliation remain separate from cached display.

## Product contract

The September 19 contract supersedes immediate card removal. A qualifying scroll-past animates the displayed section count immediately; server confirmation updates read state, and a failed read restores the displayed count. The card stays in its session position. App return, Feed-tab return, and pull-to-refresh start a new session; opening an email or profile preserves it. TODAY, YESTERDAY, and EARLIER show right-aligned X LEFT totals including unloaded historical mail. Displayed optimism never changes provider-confirmed badge or completion gates. Groups are anchored to the session date and time zone. Archived unread mail is included; Spam and Trash are excluded. Explicit Archive commits archive plus read after its undo window, so it does not return unless explicitly marked unread. The verified endpoint says **No more emails**, with optional old-post access. Viewing a post does not complete the request inside it. The app icon independently totals provider-confirmed unread email across all connected mailboxes, including archived mail but excluding Spam and Trash.

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

Approved Google Saved contacts and Other contacts supply photos after read-only consent, matched by exact email on the phone. The app server does not receive the address book. Optional iOS Contacts is a separate secondary local source. Personal and company profiles share PostView; both media and documents use three square columns with 1pt gaps. A missing photo keeps initials or the existing avatar.

The existing [Figma file’s native implementation board](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=323-742) records these changes using native DM Sans/DM Mono styles, shared components and official iOS 26 chrome. Earlier explorations remain labeled separately; source code is the reference for implemented behavior.

Native backend verification includes 16 isolated APNs/badge tests. These establish signing, routing, aggregation, unknown-count handling and alert eligibility; they do not establish live APNs delivery. The later production APNs configuration is recorded below; physical-device notification and badge delivery remain unverified.

Historical September 18 Figma verification: 12 editable native screen states and four completion/recovery/badge specimens were rendered and inspected. The original SenderProfile and document-grid components were updated, with one shared native PostView, bound Ink tokens and native text styles. The media grid deliberately shows image-loading placeholders, not invented received photos. The actual app-icon asset was reused for badge examples. A canvas constraint check found no board children outside the review section. These checks verify the design artifact, not physical-device behavior.

## September 19 full-file cleanup

The September 19 session contract supersedes the immediate-removal board. All 17 original Figma pages were inventoried, rendered and explicitly archived, including unsupported settings, superseded card variants, outdated swipe behaviors and experimental mastheads. Four canonical pages now lead the file: Start here, Native foundations, Native components and Native screens. Fifty-three editable native screen/state specimens cover the current main flows, session transitions, settings, consent and supporting routes. [The full Figma audit](./figma-audit-2026-09-19.md) records each page’s disposition, current links, render corrections and remaining verification. A live company-profile screenshot was compared structurally, and the implementation task reports successful read-in-place, tab-return, detail-return and pull-to-refresh checks. Figma also reflects incomplete-count and People failure states, plus complete sender-history loading, partial failure, verified-end and verified-empty states. Profiles span all connected accounts independently of Feed inclusion; EMAILS stays unknown until fully reconciled, and misleading THREADS/AWAITING subset counters are removed. Personal-photo consent, full backfill and physical push/release verification remain distinct; design rendering alone does not establish them.


## September 19 notification readiness audit

Read-only inspection confirmed valid local development and App Store provisioning profiles for `com.craigroberts.decisioninbox` on team `48X38356RX`. The App Store profile permits production push and expires August 31, 2027; the development profile expires September 14, 2027. An archive can carry the development profile before export re-signing, so the final exported app's production entitlement is the release check.

None of the APNs configuration names were present with a value in local `server/.env` or the current process environment. This does **not** establish Render's configuration. Chrome required sign-in to both Render and Apple Developer, and no in-app browser was connected; deployed secret-name presence, live deployment/backfill logs, and Apple key capabilities therefore remain unverified. A targeted filename-only search found one existing Apple `.p8` key in Downloads; its contents were not read and the filename does not establish APNs capability.

The server requires an APNs-enabled key, its key/team identifiers, its private key (value or secret-file path), and the app topic. Production is the TestFlight transport environment. The exact configuration contract is in [server/NOTIFICATIONS.md](../server/NOTIFICATIONS.md). No keys were created, secret values revealed, or hosting settings changed during this audit. Physical-device display, badge clearing and notification navigation remain separate acceptance checks after live configuration is confirmed.


## Final native consistency pass

The source now shares one native top-bar-leading Back control across profiles, original emails, People threads and settings detail. iOS supplies adaptive Liquid Glass and safe-area placement. Full sender history displays uninterpreted messages as **EMAIL** with their real subject/body excerpt; bounded source inspection retains content and provides retry, and empty media/file claims require successful source completion. People and direct-thread history use 50-item cursor pages, loaded-versus-complete labels, and recovery for incomplete imports.

The implementation task reported successful live feed reconciliation: 22,360 eligible unread emails (Today 0, Yesterday 51, Earlier 22,309) matched the provider total; the raw inventory was 23,134, including 774 excluded Spam/Trash messages. These are point-in-time validation counts, not fixed product copy. The app badge uses the same Spam/Trash exclusion across all connected accounts; only account inclusion can make its scope wider than Feed. This does not establish physical APNs delivery. At that earlier check Render and Apple Developer still required sign-in; the later deployment audit below supersedes that access limitation.


A later Simulator check showed an app-icon badge of 22,361 matching the then-current provider unread count. The implementation task also reported permission changing from denied to authorized with Settings reflecting ON, plus a banner delivered through local `simctl push`. These checks establish Simulator presentation and permission behavior, not remote APNs signing/routing/delivery. Notification-tap timing was being corrected and awaits its own final verification.


## Live APNs configuration

After sign-in, Apple Developer confirmed the existing APNs key is team-scoped for all topics and valid for Sandbox and Production. Its matching local key was validated as P-256, then supplied directly to Render's secret field without printing its contents. The five required production variables are now present: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC`, and `APNS_ENVIRONMENT`. No new key or access grant was created. Existing environment values were preserved.

Render deployed commit `796239b` after the configuration save and reported **Deploy succeeded | Live** at 10:59:49 AM. The variable names were verified after deployment without revealing values. This removes the missing-server-configuration blocker; physical-device APNs delivery remains unverified. The earlier read-only audit is retained as the record of the initial state. Before the restart, visible operational logs showed full-history import advancing in 500-message pages through page 19 / 9,500 messages, with incremental arrivals continuing; this is progress evidence, not a completed sender-history count.


The implementation task also reported that Hayden’s real personal contact photo is visible in the live People thread header and profile, with **12 complete emails** established for that personal profile. That validates the tested identity and total; it does not establish every sender’s complete history or all pagination paths.


A deeper filtered Render log check subsequently exposed database contention: **[conversations] archive sync failed: deadlock detected** at 11:00:36 AM, followed by **[poll] unread backlog failed: deadlock detected** and repeated **[feed] unread reconciliation failed: deadlock detected** at 11:01:53 AM. These operational errors were handed to the backend implementation task. Render being Live and APNs being configured do not establish successful mail-history reconciliation; unknown totals must remain unknown while recovery is verified.

The implementation task subsequently verified the **No more emails.** endpoint and opening old posts with the isolated DEBUG `sampleFeedZero` fixture, plus the **See old posts** preference remaining off after reopening Settings. The preference was restored to On. Real Gmail was retained and was not bulk-marked read; this does not prove a real account reached zero. These checks establish the fixture’s completion UI and preference persistence. At that checkpoint, inline CID photos, database deadlock recovery and bounded thread-source inspection still required retesting. The 100-test backend result recorded then was isolated regression evidence; the final release record supersedes that intermediate test count and deployment status.

The later 1136 Debug runtime check confirmed original-email detail no longer has a wide frosted header band: the hero reaches the sheet’s top behind separate native glass Back and More controls. The implementation task also verified immediate Hayden thread text, a real personal photo, 12 complete profile emails, all seven inline thumbnails rendered, and opening an original image in Quick Look. Amazon’s complete 5,633-email total and pagination beyond the initial 50 cards were verified separately. The earlier Gmail 403’s cause was not established; the final backend’s paced recovery resumed and advanced. These checks do not establish exhaustive mailbox completion or physical APNs delivery.
