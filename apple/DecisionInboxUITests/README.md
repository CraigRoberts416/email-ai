# Feed gesture regression checks

Run the shared **FeedGestures** scheme against a dedicated iPhone Simulator:

```sh
xcodebuild -project apple/DecisionInbox.xcodeproj -scheme FeedGestures \
  -destination 'platform=iOS Simulator,id=YOUR_QA_DEVICE_ID' \
  -packageAuthorizationProvider netrc -parallel-testing-enabled NO test
```

The suite launches `-sampleFeed`, which uses synthetic mail and skips authenticated startup. It swipes from the middle of the first post and asserts that the card actually moves at least 100 points without opening a thread. It also checks scrolling after Feed retap, after a thread closes, after returning from Saved, and while the Rive refresh is working. A normal card tap must still open mail. Each successful scenario attaches a screenshot; Xcode also records the interaction.

This suite reproduced the September 21 regression before its repair: the card-wide simultaneous long press prevented the parent pan, even though the long press never completed. Do not replace these gestures with `scrollTo` or view-model-only checks; those bypass gesture recognition. Keep button feedback scoped to its individual control.

The test target is separate from the shipping app and excluded from release archives. The existing command-line model suites remain under `apple/tests`.
