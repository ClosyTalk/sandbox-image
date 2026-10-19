#!/bin/sh
set -eu
image=$1
platform=$2
[ "$(docker image inspect "$image" --format '{{index .Config.Labels "keep-on-prune"}}')" = true ]
docker run --rm --platform "$platform" --network none --cap-drop ALL --cap-add CHOWN \
  --security-opt no-new-privileges --entrypoint /bin/sh "$image" -ec '
    test "$(id -u)" = 0
    test -x /execd
    help=$(/execd --help 2>&1)
    printf "%s\n" "$help" | grep "Version.*docker/execd/v1.0.20"
    printf "%s\n" "$help" | grep -F "go1.27.2"
    printf "%s\n" "$help" | grep -F "ae452d4af7b6415b5074fd7e075b97ff7a5ac236"
    test ! -e /execd.exe
    test ! -e /opensandbox-supervisor
    for file in /execd /bootstrap.sh /install.bat /usr/local/bin/bwrap; do
      test "$(stat -c %u:%g "$file")" = 0:0
    done
    test "$(stat -c %a /execd)" = 755
    test "$(stat -c %a /bootstrap.sh)" = 755
    test "$(stat -c %a /install.bat)" = 644
    /usr/local/bin/bwrap --version | grep -Fx "bubblewrap 0.11.2"
    echo "7d684b4bd0b9d78c2a915a18cca074ee59a1e8cdf2fe077714cc16c30c4d77a7  /bootstrap.sh" | sha256sum -c -
    echo "0306ada1775dc20d65fc17df5894aad0417346061818033a4354ce9113e5b0ec  /install.bat" | sha256sum -c -
    mkdir /tmp/legacy
    printf evidence > /tmp/legacy/file
    ln -s /etc/passwd /tmp/legacy/link
    find /tmp/legacy -xdev -user 0 -exec chown -h 10001:10001 {} +
    test "$(stat -c %u /tmp/legacy/file)" = 10001
    test "$(stat -c %u /etc/passwd)" = 0
    test "$(cat /tmp/legacy/file)" = evidence
  '

# Validate the image release separately from the preserved upstream binary version.
version=$(cat "$(dirname "$0")/EXECD_VERSION")
actual=$(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.version"}}')
case "$actual" in
  "$version"|"$version"-rebuild.*) ;;
  *) echo "Unexpected image version: $actual (expected $version or its rebuild)" >&2; exit 1 ;;
esac
[ "$(docker image inspect "$image" --format '{{.Architecture}}')" = "${platform##*/}" ]
[ "$(docker image inspect "$image" --format '{{json .Config.Entrypoint}}')" = '["./execd"]' ]
[ "$(docker image inspect "$image" --format '{{.Config.User}}')" = '' ]
[ "$(docker image inspect "$image" --format '{{.Config.WorkingDir}}')" = / ]
[ "$(docker image inspect "$image" --format '{{json .Config.Cmd}}')" = null ]
[ "$(docker image inspect "$image" --format '{{json .Config.Env}}')" = '["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]' ]
[ "$(docker image inspect "$image" --format '{{index .Config.Labels "io.closytalk.execd.go.version"}}')" = go1.27.2 ]

# Exercise the default entrypoint and real API entirely offline, without a host port.
container=$(docker run -d --platform "$platform" --network none --cap-drop ALL \
  --security-opt no-new-privileges "$image")
trap 'docker rm -f "$container" >/dev/null' EXIT HUP INT TERM
docker exec "$container" /bin/sh -ec '
  i=0
  until wget -S -q -O /tmp/ping.json http://127.0.0.1:44772/ping 2>/tmp/ping.headers; do
    i=$((i + 1))
    test "$i" -lt 30
    sleep 1
  done
  grep -F "HTTP/1.1 200 OK" /tmp/ping.headers
  test ! -s /tmp/ping.json
  echo "GET /ping: HTTP 200, empty body (upstream contract)"
'
