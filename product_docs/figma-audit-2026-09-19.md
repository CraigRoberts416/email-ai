# Figma reconciliation — September 19, 2026

The entire existing Email App Component Library was audited against `apple/DecisionInbox`. The visual identity stays monochrome, with DM Sans for human content, DM Mono for interpretation/instrumentation, and native iOS navigation. This is a cleanup of the existing file, not a new visual direction.

## Current starting points

- [Start here](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=337-2): file navigation, source-of-truth rules and confirmed reading contract.
- [Native foundations](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=338-21): bound Ink variables, native type roles, spacing, contrast and accessibility rules.
- [Native components](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=334-635): PostView read/unread variants, shared SenderProfile, circular AvatarView, square media/document grids and on/off InkToggle variants. Existing component IDs were preserved where updated.
- [Main native states](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=323-742): feed, verified endpoint, old posts, people/company profiles, grids, feed/photo/notification settings, People, failure and badge specimens.
- [Session comparison](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=341-780): unread, read-in-place, fresh-session removal, verified zero, and Today/Yesterday/Earlier count rules.
- [Current settings and consent](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=339-616): working Settings, AI facts, unsubscribe receipts, storage disclosure, Google consent, photo recovery, privacy controls and denied notification permission.
- [Live loading and recovery states](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=348-1135): loaded cards with unknown totals, People refresh failure with and without cached conversations, and a single-back-control profile contract.
- [Full sender history](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=349-2890): all-account loading, partial failure, verified end and verified empty.
- [History continuity](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=354-1602): original-email posts, source-inspection pending/retry/verified-empty, People inventory states and thread pagination.
- [Core routes](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=343-1039): original email, Compose, Search, Saved, mailbox detail/list, provider selection and unsubscribe run receipt.

These boards contain 53 editable screen/state specimens. Sample message text, counts and run receipts are explicitly illustrative. Media grids show placeholders rather than invented received images. The actual app-icon asset is reused for badge examples. Google contact photos remain real authorized identity data, not generated portraits.

## Whole-file audit and disposition

All 17 original pages remain available, renamed `Archive · …`, each with a visible historical notice and a pointer to the canonical pages. Old reusable components are prefixed `Archive/`; old text styles are likewise separated. Historical content was retained rather than destructively deleted.

| Original page | Main mismatch found | Current disposition |
|---|---|---|
| Card | Contained cards, old action targets, obsolete component states | Archived; native PostView/profile/grids moved to current component page. |
| App Screens | Old All Mail navigation, mark-unread/label/block concepts | Archived; current main and core route boards replace the implementation reference. |
| App Screens v2 — social | Competing compact/lead card and feed-completion treatments | Archived; one shared native PostView. |
| Design System | Old typography, contrast values and SF Pro Display references | Archived; native token/type foundations now lead the file. |
| Flows · Onboarding & Accounts | Provider and consent assumptions, including obsolete contact-access promise | Archived; current supported-provider and Google photo-consent states provided. |
| Flows · Settings | Unwired density, ranking, AI, retention, analytics and sender controls | Archived; actual native settings and facts replace them. |
| Flows · Feed & Posts | Immediate removal and outdated swipe/action behavior | Archived; stable-session contract and rolling counts are canonical. |
| Flows · Thread & Compose | Older thread/card treatment and speculative composer controls | Archived; native original-mail and shared composer routes provided. |
| Edge cases & stress | Stress cases built on the superseded card system | Archived; current components govern new stress work. |
| Feed · Media, HTML & carousel | Competing image/HTML/card shapes | Archived; current shared posts and square profile grids are authoritative. |
| Flows · Completing the set | Speculative ranking, label/block, quiet-hours and composer options | Archived; not a list of implemented capabilities. |
| Hero image system | Historical prompt and imagery exploration | Archived; current server prompt and received media remain distinct. |
| Feature · Unsubscribe agent | Old entry points, batch selection and local-blocking implications | Archived; actual tray/run receipts and native actions are authoritative. |
| Feature · Many mailboxes | Some supported scale rules mixed with unsupported per-account settings | Archived; current list/detail/settings screens and source thresholds documented. |
| Direct Messages | Old identity, thread and group components | Archived; canonical People/profile identities and real-photo sources replace them. |
| Feed · Masthead options | Rejected fonts and obsolete “as shipped” variants | Archived; current DM Sans/DM Mono masthead preserved. |
| Card V2 | Alternative avatars, reaction rows and post candidates | Archived; current components have an unambiguous home. |

## Contract reconciliation

A real forward scroll fully past a post immediately animates its displayed section count downward. Server confirmation marks it read; failure restores the displayed count. The post stays in its active session; read styling changes sender weight and quote ink while the ground stays white. App return, Feed-tab return and pull-to-refresh start a fresh session. Email/profile navigation preserves the current one.

All historical eligible unread mail is included, including archived unread; Spam and Trash are excluded. TODAY, YESTERDAY and EARLIER show right-aligned X LEFT counts, including unloaded mail. The displayed optimistic decrement never substitutes for provider-confirmed badge or completion state; card styling stays frozen during active scrolling. The session date and IANA time zone keep grouping stable across midnight. A page-size limit never establishes completion.

“No more emails” means all eligible unread history is accounted for, not that every card above is already read. Only verified zero, with no pending arrivals, offers the optional See old posts shortcut. Archive commits archive plus read after its undo window; Undo cancels both. The badge separately totals provider unread counts across every connected account, including archived unread but excluding Spam/Trash. It may remain positive after Feed is clear when connected accounts are excluded from Feed.

Profiles now require full retained read, unread and archived history across **all connected mailboxes**, independent of Feed inclusion, excluding Spam/Trash. People match exact email; companies combine their canonical registrable domain and subdomains. Shared/free email domains never aggregate unrelated people. EMAILS remains unknown until every account has reconciled, and THREADS/AWAITING subset counters are removed. Loading and failure retain cached posts; only verified end/zero use their respective completion copy. This history contract is represented by the current implementation and design states; the earlier screenshot showing a loaded-feed subset does not establish complete-history correctness.

Google Saved contacts and Other contacts use read-only consent and exact-email matching on the phone. Google photo, permitted device photo, supplied identity/logo, then initial is the fallback order. Missing grants expose per-account reconnect; failed refresh exposes retry. The address book is not sent through the app server.

## Verification and remaining boundaries

- Read audit covered all original pages, component inventories and relevant copy. Whole-page renders covered all 17 archives; canonical boards were rendered and visually inspected. Render review caught and fixed a clipped foundations board, toggle bounds, tab selection, consent/provider labels, read-state styling and stale completion copy.
- Canonical board bounds checks found no children outside documentation/review boards, and a current-page text audit found no superseded immediate-removal, false-clear, or obsolete Google-button copy. Phone viewports intentionally clip scrollable content.
- Current components reuse bound native colors and named text styles; official iOS 26 tab-bar components are reused. Native font metrics, Dynamic Type, glass, keyboard placement and scroll behavior remain runtime-owned. Core-route boards are source-aligned structural references, not a claim of pixel-identical system rendering.
- The earlier Expo review and JavaScript tests are historical and do not prove native correctness. Earlier September 18 screenshots do not validate the September 19 session contract.
- A September 19 live Simulator company-profile screenshot was inspected for structure only: banner, circular logo, shared identity/lane layout and PostView are visible. The later native back-navigation refinement replaces the manual banner overlay with one shared system toolbar control; final rendering is checked separately below. No private email content or contact photos were copied into Figma.
- The implementation task reports successful live checks: two scrolled-past cards changed to read and retained their order; Feed-tab return removed read cards; opening/closing an email preserved its read card; pull-to-refresh removed it. These reports support those specific session transitions. App-background return is not established by those specific transition checks. The later complete-backfill result is recorded below.
- Historical counts were still reconciling during the first live check. Figma now distinguishes **200 LOADED** from a complete unread total and shows **…** in unknown section counts. People failures have retry and preserve cached rows, never a false successful-empty claim.
- The implementation task later reported a real personal contact photo in the tested People header and profile, plus a verified total of 12 emails for that personal profile. That specific runtime result does not establish every sender’s history, all pagination paths, physical-device APNs delivery or TestFlight distribution; design rendering alone establishes none of these runtime checks.
- This is an editable design reference, not a fully wired Figma prototype of every native gesture or provider/system sheet. Google and iOS permission sheets remain platform-owned; no fake provider UI is presented as implemented.

Local render artifacts are in `/tmp/figma-audit-2026-09-19/`; the shared Figma links above are the durable review surface. Native release results belong in the implementation task’s release record.


## Final source and live reconciliation

The implementation task later reported verified full-feed completion: section totals 0 / 51 / 22,309 matched the eligible provider total 22,360; 774 Spam/Trash messages explained the larger raw inventory. Badge scope now also excludes Spam/Trash, while still including all connected accounts and archived unread mail. These live counts are evidence only and were not copied into illustrative Figma screens.

Source alignment adds original-email PostView content, bounded attachment/image inspection with retry, and complete People/thread cursor pagination. Loaded counts remain explicitly labeled until exhaustive inventory establishes totals. Empty media/document states require successful inspection of every relevant source. Shared native back navigation uses system safe-area placement and adaptive iOS 26 material, without a separate fixed-position banner button.


The 10:47 live Simulator company-profile image was inspected structurally: the back action is now in the standard native toolbar position and uses translucent system material, while the banner/avatar layout remains intact. No private content was transferred to Figma. Current editable screens share a reusable BackNavigation component; static glass colors and safe-area dimensions are reference samples, while the OS remains authoritative at runtime. Original-email PostView variants retain real-source labels and no generated summary. Fifty-three screen/state specimens now cover the consolidated current design.


Final render review covered the updated main, supporting, core-route, full-history, new continuity, and component boards. It corrected toolbar-title constraints, selected profile-lane underlines, card-library bounds, a resized avatar radius, and obsolete People obligation labels. The Simulator home-screen badge was also inspected at 22,361; the implementation task reported that this matched the live provider count. Local simulated push and permission checks are distinct from still-unverified remote APNs delivery.


The final interaction refinement adds two count-transition specimens: immediate **7 LEFT → 6 LEFT** at a qualifying scroll-past, and **6 LEFT → 7 LEFT** on read failure. Both section names and LEFT are uppercase. These static state specimens document the native numeric animation; they are not a Figma motion prototype. Card read styling waits for confirmation and remains frozen during active scrolling. Provider-confirmed counts still govern badges and completion.


A later live backend check found database deadlocks during archive/unread reconciliation despite the successful deployment. The implementation task owns the fix and retest. Earlier point-in-time verified totals do not make subsequent error states complete; the loading/retry specimens and provider-confirmation gates remain applicable. Production APNs configuration is now deployed, while physical remote delivery remains pending.

The implementation task also reported the real-account **No more emails.** endpoint, opening old posts, and an off preference persisting after Settings reopened; **See old posts** was restored to On afterward. These checks support the existing completion and preference specimens. Inline CID image recovery and the final backend/native release remain under retest; they are not inferred from successful Figma rendering.

The existing partial-thread specimen now includes **Loading original emails and files…** beneath cached text. Its recovery annotation records the six-attempt loaded-page inspection, transport/exhaustion copy and retained messages. The notification specimen documents **Opening email…** and the native **Couldn’t open email** alert with **Try again** / **Cancel**, including cold-launch buffering and mailbox-scoped routing. Both affected boards were rendered and inspected after this final edit; the cached text, loading footer, reply control and notes remain visible without clipping. These are source-aligned states; final runtime release checks remain separate.
