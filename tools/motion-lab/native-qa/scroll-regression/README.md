# September 21 scroll regression evidence

- `card-swipe.png`: synthetic feed after a real card-origin touch swipe.
- `refresh-swipe.png`: feed moved while the Rive receipt renders in the reserved refresh strip.
- `upload-2609210445.jpg`: Xcode Organizer's exact-build upload confirmation.

The original recognizer failed the native card-origin swipe test. Removing it passed the same test and all four expanded gesture scenarios on both iOS 26.5 and iOS 26.4.1 (eight total). These stills are supporting layout evidence; the native assertions and retained `.xcresult` event traces establish movement. See [release record](../../../../product_docs/native-release-2609210445.md) for scope and remaining distribution checks.
