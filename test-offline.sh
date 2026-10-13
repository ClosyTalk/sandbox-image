#!/bin/sh
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
image=${1:?Usage: sh test-offline.sh IMAGE [PLATFORM]}
platform=${2:-linux/arm64}
test "$(docker image inspect "$image" --format '{{index .Config.Labels "keep-on-prune"}}')" = true
docker run --rm --init --platform "$platform" --network none \
  --cap-drop ALL --security-opt no-new-privileges --shm-size 256m \
  --mount "type=bind,source=$repo/tests,target=/tests,readonly" \
  "$image" python3 /tests/offline.py
