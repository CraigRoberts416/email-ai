#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h:h}"
test_binary="$(mktemp -t decision-inbox-send-tests)"
recovery_directory="$(mktemp -d -t decision-inbox-compose-recovery)"
trap 'rm -f "$test_binary"; rm -rf "$recovery_directory"' EXIT
python3 - "$project_root/apple/DecisionInbox/Features/Compose/ComposeView.swift" "$recovery_directory/ComposeRecoveryState.swift" <<'PY_SOURCE'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
recovery = source.split("// BEGIN COMPOSE_RECOVERY_STATE\n", 1)[1].split("// END COMPOSE_RECOVERY_STATE", 1)[0]
Path(sys.argv[2]).write_text(recovery)
PY_SOURCE
swiftc -swift-version 5 -parse-as-library \
  "$recovery_directory/ComposeRecoveryState.swift" \
  "$project_root/apple/DecisionInbox/Model/Message.swift" \
  "$project_root/apple/DecisionInbox/Model/UnsubscribeRun.swift" \
  "$project_root/apple/DecisionInbox/Services/AccountConnectionPolicy.swift" \
  "$project_root/apple/DecisionInbox/Services/InteractionArchive.swift" \
  "$project_root/apple/DecisionInbox/Services/MailDraftStore.swift" \
  "$project_root/apple/DecisionInbox/Services/DiscussionStore.swift" \
  "$project_root/apple/DecisionInbox/Model/Conversation.swift" \
  "$project_root/apple/DecisionInbox/Model/FeedSession.swift" \
  "$project_root/apple/DecisionInbox/Model/FeedPaginationLifecycle.swift" \
  "$project_root/apple/DecisionInbox/Services/NotificationTapBuffer.swift" \
  "$project_root/apple/DecisionInbox/Services/APIClient.swift" \
  "$project_root/apple/DecisionInbox/Model/FeedStore.swift" \
  "$project_root/apple/tests/FeedStoreHarness.swift" \
  "$project_root/apple/tests/SendLifecycleTests.swift" \
  -o "$test_binary"
"$test_binary"
