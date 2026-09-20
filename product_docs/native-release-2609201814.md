# People tab unread badge · 1.0 (2609201814)

Adds a native numbered badge to People. Its unit is unread conversations, matching the People masthead, not individual unread emails. Complete history uses the verified aggregate beyond loaded rows; incomplete inventory uses known loaded unread conversations. Zero hides the badge, and failed refresh preserves existing state.

The count loads while Feed is visible, refreshes on app/mail/read reconciliation, and polls every 30 seconds while active. Visiting People alone does not mark mail read. The existing conversation-opening read policy is a separate question sent to the user; this change does not change message read semantics.

Validation: 141 production FeedStore integration checks passed, including eight additional checks covering count units, unloaded aggregate, unavailable aggregate, refresh failure, live read to zero and new arrival. Debug Simulator build passed. On the signed-in iPhone 17 Pro / iOS 26.4 Simulator, People showed 9 while Feed was selected; opening People showed the matching 9 UNREAD LOADED. No message content was changed by this badge check.

Spec and canonical tabbed Figma screens updated. This release retains the prior feed-read/count/navigation fixes from 2609201801 and excludes unrelated app-interaction-craft work.

Release archive/upload status will be recorded after completion. TestFlight group availability remains a separate verification; the earlier Chrome extension-panel blocker has not yet been cleared by the user.
