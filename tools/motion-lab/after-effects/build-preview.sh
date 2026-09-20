#!/bin/sh
set -eu
cd "$(dirname "$0")"
# Frames are native AE renders; this only joins/encodes them at their authored rate.
# Left: 240 ms entrance. Right: 720 ms entrance. No sound or timing interpolation.
ffmpeg -hide_banner -loglevel error -y \
  -framerate 30 -i frames-240/frame-%03d.png \
  -framerate 30 -i frames-720/frame-%03d.png \
  -filter_complex '[0:v][1:v]hstack=inputs=2,format=yuv420p[out]' \
  -map '[out]' -c:v libx264 -preset medium -crf 18 \
  -movflags +faststart -an -t 2 receipt-comparison.mp4
