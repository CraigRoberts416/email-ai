#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h:h}"
test_directory="$(mktemp -d -t decision-inbox-notification-delegate)"
trap 'rm -rf "$test_directory"' EXIT
python3 - "$project_root/apple/DecisionInbox/Services/PushService.swift" "$test_directory/Delegate.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('extension AppDelegate: UNUserNotificationCenterDelegate {')
end = source.index('/// Bridges the two UIKit callbacks', start)
Path(sys.argv[2]).write_text('import Foundation\n' + source[start:end])
PY
swiftc -swift-version 5 -parse-as-library \
  "$project_root/apple/DecisionInbox/Services/NotificationTapBuffer.swift" \
  "$test_directory/Delegate.swift" \
  "$project_root/apple/tests/NotificationDelegateTests.swift" \
  -o "$test_directory/notification-delegate-tests"
"$test_directory/notification-delegate-tests"
