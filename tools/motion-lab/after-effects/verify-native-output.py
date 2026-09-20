#!/usr/bin/env python3
"""Verify recorded AE responses and native PNG output; never talks to After Effects."""
import hashlib
import json
import pathlib
import struct
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent


def command(*args):
    return subprocess.check_output(args)


def pixels(name):
    return command("ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(ROOT / name),
                   "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1")


def compare(left, right):
    a, b = pixels(left), pixels(right)
    assert len(a) == len(b) == 640 * 360 * 4
    changed = [i // 4 for i in range(0, len(a), 4) if a[i:i + 4] != b[i:i + 4]]
    return {"left": left, "right": right, "changedPixels": len(changed),
            "bounds": [min(i % 640 for i in changed), min(i // 640 for i in changed),
                       max(i % 640 for i in changed) + 1, max(i // 640 for i in changed) + 1]
            if changed else None}


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


record = json.loads((ROOT / "verification.json").read_text())
source = json.loads((ROOT / "executed-native-receipt.json").read_text())
layers = record["layers"]["result"]["layers"]
assert len(layers) == 5
tracks = [{"layer": layer["name"], "property": prop["name"], "keys": prop["keyframes"]}
          for layer in layers for prop in walk(layer) if "keyframes" in prop]
assert len(tracks) == 5
for track in tracks:
    assert len(track["keys"]) == 2
    assert track["keys"][0]["time"] == 0
    assert abs(track["keys"][1]["time"] - 0.72) < 0.0001
    assert all(k["inInterp"] == k["outInterp"] == 6612 for k in track["keys"])
assert all(not layer["effectsGroup"] and not layer["masksGroup"] for layer in layers)
assert not [op for op in source["arguments"]["args"]["ops"] if op["operation"].startswith("expression.")]
assert not [item for item in walk(record["layers"]) if item.get("expressionError")]

sequences = []
for name in ["frames-240", "frames-720"]:
    files = sorted((ROOT / name).glob("frame-*.png"))
    assert [f.name for f in files] == [f"frame-{i:03d}.png" for i in range(60)]
    for f in files:
        data = f.read_bytes()
        assert data[:8] == b"\x89PNG\r\n\x1a\n"
        assert struct.unpack(">II", data[16:24]) == (640, 360)
    command("ffmpeg", "-hide_banner", "-loglevel", "error", "-framerate", "30", "-i",
            str(ROOT / name / "frame-%03d.png"), "-f", "null", "-")
    sequences.append({"directory": name, "frames": len(files), "size": [640, 360],
                      "bytes": sum(f.stat().st_size for f in files), "decodePassed": True})

comparisons = [compare("240-start.png", "720-start.png"),
               compare("240-middle.png", "720-middle.png"),
               compare("240-settled.png", "720-settled.png"),
               compare("240-settled.png", "content-edit.png")]
assert comparisons[0]["changedPixels"] == comparisons[2]["changedPixels"] == 0
assert comparisons[1]["changedPixels"] > 0 and comparisons[3]["changedPixels"] > 0
preview = json.loads(command("ffprobe", "-v", "error", "-show_entries",
    "stream=codec_name,width,height,pix_fmt,r_frame_rate,nb_frames,duration", "-show_entries",
    "format=size,duration", "-of", "json", str(ROOT / "receipt-comparison.mp4")))
stream = preview["streams"][0]
assert (stream["codec_name"], stream["width"], stream["height"], stream["r_frame_rate"],
        stream["nb_frames"], float(stream["duration"])) == ("h264", 1280, 360, "30/1", "60", 2.0)

result = {"status": "PASS", "checkedOn": "2026-09-20", "stillTimesSeconds": [0, 0.12, 1], "nativeLayerCount": len(layers),
          "animatedPropertyCount": len(tracks), "keyframeCount": sum(len(t["keys"]) for t in tracks),
          "tracks": tracks, "interpolationEnum": 6612,
          "expressionOperationsAuthored": 0, "reportedExpressionErrors": [],
          "effectsAndMasks": 0, "sequences": sequences, "pixelComparisons": comparisons,
          "preview": preview, "previewLayout": "240 ms left; 720 ms right",
          "checksums": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                        for name in ["receipt-study.aep", "before-fixture.aep", "receipt-comparison.mp4",
                                     "executed-native-receipt.json", "verification.json"]}}
(ROOT / "post-render-verification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({"status": result["status"], "tracks": len(tracks), "comparisons": comparisons,
                  "preview": stream}, indent=2))
