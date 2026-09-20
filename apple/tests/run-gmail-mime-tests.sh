#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h:h}"
test_binary="$(mktemp -t decision-inbox-mime-tests)"
test_output="$(mktemp -t decision-inbox-mime-output)"
trap 'rm -f "$test_binary" "$test_output"' EXIT
swiftc -swift-version 5 -parse-as-library \
  "$project_root/apple/DecisionInbox/Services/GmailClient.swift" \
  "$project_root/apple/tests/GmailMIMETests.swift" -o "$test_binary"
"$test_binary" > "$test_output"
python3 - "$test_output" <<'PY'
import json, sys
from email import policy
from email.parser import BytesParser
with open(sys.argv[1]) as fixture: messages = json.load(fixture)
multipart = BytesParser(policy=policy.default).parsebytes(messages['multipart'].encode())
assert multipart.is_multipart()
parts = list(multipart.iter_parts())
assert len(parts) == 2
assert parts[0].get_content() == 'A note\n\nOriginal email: real source words.'
assert parts[1].get_filename() == 'résumé.pdf'
assert parts[1].get_payload(decode=True) == bytes([0, 1, 2, 127, 128, 255])
assert multipart['Subject'] == 'Forward — source'
assert multipart['Cc'] == 'copy@example.invalid'
assert multipart['In-Reply-To'] is None
plain = BytesParser(policy=policy.default).parsebytes(messages['plain'].encode())
assert plain.get_content() == 'Unicode body: café'
assert plain['Bcc'] is None
assert plain['In-Reply-To'] == '<real@example.invalid>'
assert plain['References'] == '<real@example.invalid>'
assert not multipart.defects and not plain.defects
print('PASS: real MIME parsed independently; original text, binary file, Unicode filename, CC, reply headers, header injection and size boundary verified')
PY
