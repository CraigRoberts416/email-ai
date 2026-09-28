# Native release 1.0 (2609281900)

September 28, 2026. Implementation commit `969228b0b6ae8e5d4e72b34d052f06237c74fcf6`. Adds **You → Feed → Clear unread backlog**, with All unread / Before a date, mailbox selection, exact preview, native confirmation, bounded progress and Pause/Resume. Mail remains in Gmail and searchable. The existing feed and robot animation are carried forward.

## Verification

- 204 native model/transport checks passed. The server's full 139-test run and final eight backlog tests passed, including 22,000 identities, ownership, HTTP authentication, expired previews, SQL rollback and revision preservation.
- Two control UI tests passed in 46.592 seconds. Two existing feed gesture/session regressions passed in 41.076 seconds. All four had zero failures. These are Simulator checks, not a physical-device performance claim.
- The deployed backend and signed-in Recovery Simulator completed a read-only preview of 21,491 eligible unread emails. No live bulk mark-read operation was approved or executed during testing.
- [Retained synthetic screenshots and evidence](../tools/native-qa/backlog-cleanup/README.md). The editable [Figma control board](https://www.figma.com/design/LlstGMGXZrDiY2Ee4dd3yl/Email-App-Component-Library?node-id=396-1880) and existing Feed settings entry were visually checked.

## Deployment

Render reports commit `969228b` **Live**, deploy `dep-datf24gu01pc73f88bp0`, duration 1m34s. The unauthenticated cleanup endpoint returns 401, and the authenticated Simulator preview succeeds. The additive `backlog_jobs` schema migration ran with the production service.

The Release archive succeeded. Bundle identifier, version/build, strict code signature, absence of DEBUG sample flags and absence of test bundles were checked. The bundled Rive SHA-256 remains `ae690c2f817d3df4a4efce5eaeea8711aea78c5cd9e1695a3202cf7ff89d08a7`.

**Xcode recorded successful upload to Apple at 19:03:23 Eastern**, with no upload errors or warnings, for build **2609281900**. [Upload receipt](../tools/native-qa/backlog-cleanup/upload-2609281900.json). Archive: `~/Library/Developer/Xcode/Archives/2026-09-28/DecisionInbox 2026-09-28 19.00.xcarchive`.

Apple processing completion and Internal-group availability remain unverified because the App Store Connect web session is signed out. The user has been asked to sign in. No external beta review or public App Store submission was made.
