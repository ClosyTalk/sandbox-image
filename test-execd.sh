#!/bin/sh
set -eu
image=$1
platform=$2
[ "$(docker image inspect "$image" --format '{{index .Config.Labels "keep-on-prune"}}')" = true ]
docker run --rm --platform "$platform" --network none --cap-drop ALL --cap-add CHOWN \
  --security-opt no-new-privileges --entrypoint /bin/sh "$image" -ec '
    test "$(id -u)" = 0
    test -x /execd
    /execd --help 2>&1 | grep "Version.*docker/execd/v1.0.20"
    mkdir /tmp/legacy
    printf evidence > /tmp/legacy/file
    ln -s /etc/passwd /tmp/legacy/link
    find /tmp/legacy -xdev -user 0 -exec chown -h 10001:10001 {} +
    test "$(stat -c %u /tmp/legacy/file)" = 10001
    test "$(stat -c %u /etc/passwd)" = 0
    test "$(cat /tmp/legacy/file)" = evidence
  '
