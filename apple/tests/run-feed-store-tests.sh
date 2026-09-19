#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h:h}"
test_binary="$(mktemp -t decision-inbox-feed-store)"
trap 'rm -f "$test_binary"' EXIT
swiftc -swift-version 5 -parse-as-library \
  "$project_root/apple/DecisionInbox/Model/Message.swift" \
  "$project_root/apple/DecisionInbox/Model/Conversation.swift" \
  "$project_root/apple/DecisionInbox/Model/FeedSession.swift" \
  "$project_root/apple/DecisionInbox/Model/FeedPaginationLifecycle.swift" \
  "$project_root/apple/DecisionInbox/Services/NotificationTapBuffer.swift" \
  "$project_root/apple/DecisionInbox/Services/APIClient.swift" \
  "$project_root/apple/DecisionInbox/Model/FeedStore.swift" \
  "$project_root/apple/tests/FeedStoreHarness.swift" \
  "$project_root/apple/tests/FeedStoreTests.swift" \
  -o "$test_binary"
"$test_binary"
