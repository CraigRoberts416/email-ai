#!/usr/bin/env python3
"""Exercise the local synthetic Rive fixture; no server, account or app required."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import zlib

PROJECT = Path(__file__).resolve().parent
BUILD = PROJECT / "build"
RIVE = os.environ.get("RIVE_BIN", str(Path.home() / ".rive/bin/rive"))
COMMANDS = []


def run(*arguments):
    command = [RIVE, *map(str, arguments)]
    COMMANDS.append(command)
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    return result.stdout


def png_signature(path):
    """Hash PNG image data without ancillary metadata; same renderer per run."""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    offset, compressed, header = 8, bytearray(), None
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            header = payload
        elif kind == b"IDAT":
            compressed.extend(payload)
        offset += length + 12
    assert header is not None
    assert struct.unpack(">II", header[:8]) == (440, 252)
    return hashlib.sha256(header + zlib.decompress(compressed)).hexdigest()


def capture(name, phase, *arguments, reduce_motion=False, semantics=False):
    image = BUILD / f"{name}.png"
    data = BUILD / f"{name}.json"
    args = [PROJECT, f"--screenshot={image}", f"--data-dump={data}", *arguments]
    if semantics:
        args.append(f"--semantics={BUILD / 'semantics.json'}")
    run(*args)
    state = json.loads(data.read_text())
    properties = {p["path"]: p["value"] for p in state["viewModel"]["properties"]}
    assert properties["phase"] == phase, (name, properties)
    assert properties["reduceMotion"] == reduce_motion, (name, properties)
    return {"phase": phase, "reduceMotion": reduce_motion,
            "pngImageDataSHA256": png_signature(image)}


def main():
    BUILD.mkdir(exist_ok=True)
    version = run("--version").strip()
    verify = json.loads(run(PROJECT, "--verify", "--format=json"))
    assert verify["success"] and not verify["errors"] and not verify["warnings"]
    summary = json.loads(run("inspect", PROJECT, "--summary"))
    assert not summary["problems"]
    types = summary["artboards"][0]["types"]
    assert types["StateMachine"] == 1 and types["AnimationState"] == 4
    results = {
        "idle": capture("idle", 0, "--data=phase=0", "--advance=30", semantics=True),
        "active": capture("active", 1, "--data=phase=1", "--advance=30"),
        "success": capture("success", 2, "--data=phase=2", "--advance=30"),
        "active_later": capture("active-later", 1, "--data=phase=1", "--advance=60"),
        "reduced": capture("reduced-motion", 1, "--data=phase=1",
                           "--data=reduceMotion=true", "--advance=30", reduce_motion=True),
        "reduced_later": capture("reduced-motion-later", 1, "--data=phase=1",
                                 "--data=reduceMotion=true", "--advance=90", reduce_motion=True),
        "pointer_active": capture("pointer-active", 1, "--advance=1",
                                  "--pointer=click@220,220", "--advance=30"),
        "semantic_success": capture("semantic-success", 2, "--advance=1",
                                    "--semantic-action=tap@Success", "--advance=30"),
        "interrupted": capture("interrupted", 0, "--advance=1", "--pointer=click@220,220",
                               "--advance=3", "--pointer=click@86,220", "--advance=30"),
        "rapid_success": capture("rapid-success", 2, "--advance=1", "--pointer=click@220,220",
                                 "--advance=3", "--semantic-action=tap@Success", "--advance=30"),
    }
    signature = lambda name: results[name]["pngImageDataSHA256"]
    assert len({signature("idle"), signature("active"), signature("success")}) == 3
    assert signature("active") != signature("active_later"), "Active must animate."
    assert signature("reduced") == signature("reduced_later"), "Reduced Motion must remain static."
    assert signature("semantic_success") == signature("success")
    assert signature("interrupted") == signature("idle"), "Rapid return must settle to Idle."
    assert signature("rapid_success") == signature("success"), "Rapid update must settle to Success."
    semantics = json.loads((BUILD / "semantics.json").read_text())
    assert [(n["role"], n["label"]) for n in semantics["roots"]] == [
        ("button", "Idle"), ("button", "Active"), ("button", "Success")]
    assert all(n["bounds"]["height"] >= 44 for n in semantics["roots"])
    report = {"success": True, "cli": version, "verify": verify,
              "summary": summary, "captures": results, "commands": COMMANDS}
    (BUILD / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {version}; compile + structure + 10 captures + semantics + motion + interruptions")
    print(f"Evidence: {BUILD / 'verification.json'}")


if __name__ == "__main__":
    main()
