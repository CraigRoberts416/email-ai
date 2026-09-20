"""Install the documented Motion+ alias without saving the credential."""

import getpass
import os
from pathlib import Path
import subprocess
import tempfile

lab = Path(__file__).resolve().parent
token = getpass.getpass("Motion package token (hidden): ")
if not token:
    raise SystemExit("No credential supplied; nothing changed.")

with tempfile.TemporaryDirectory(prefix="motion-lab-npm-") as cache:
    result = subprocess.run(
        ["npm", "install", "--save-exact", "motion-plus@npm:@motionplus/core@latest",
         "--no-audit", "--no-fund", "--loglevel=error", "--logs-max=0",
         "--fetch-retries=0", "--fetch-timeout=45000", "--cache", cache],
        cwd=lab,
        env={**os.environ, "MOTION_TOKEN": token},
        text=True,
        capture_output=True,
        timeout=90,
    )
    output = (result.stdout + result.stderr).replace(token, "[REDACTED]")
    print(output[-3000:])

for path in lab.iterdir():
    if path.is_file() and token.encode() in path.read_bytes():
        raise SystemExit("Credential unexpectedly found in a lab file; review required.")
print("Credential scan: clear; temporary npm cache removed.")
raise SystemExit(result.returncode)
