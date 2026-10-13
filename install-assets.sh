#!/bin/sh
set -eu
. /build/downloads.env
case "$1" in
  amd64) node_arch=x64; node_hash=$NODE_AMD64_SHA256; browser_hash=$AGENT_BROWSER_AMD64_SHA256 ;;
  arm64) node_arch=arm64; node_hash=$NODE_ARM64_SHA256; browser_hash=$AGENT_BROWSER_ARM64_SHA256 ;;
  *) echo "Unsupported architecture: $1" >&2; exit 1 ;;
esac
fetch() {
  curl --fail --show-error --silent --location --retry 3 "$1" -o "$2"
  printf '%s  %s\n' "$3" "$2" | sha256sum --check --status
}
mkdir -p /opt/node /opt/agent-browser-skills /usr/local/share/licenses/agent-browser
fetch "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" /tmp/node.tar.xz "$node_hash"
tar -xJf /tmp/node.tar.xz --strip-components=1 -C /opt/node
fetch "https://github.com/vercel-labs/agent-browser/releases/download/v${AGENT_BROWSER_VERSION}/agent-browser-linux-${node_arch}" /usr/local/bin/agent-browser "$browser_hash"
chmod 755 /usr/local/bin/agent-browser
fetch "https://codeload.github.com/vercel-labs/agent-browser/tar.gz/refs/tags/v${AGENT_BROWSER_VERSION}" /tmp/agent-browser.tar.gz "$AGENT_BROWSER_SOURCE_SHA256"
mkdir /tmp/agent-browser-source
tar -xzf /tmp/agent-browser.tar.gz --strip-components=1 -C /tmp/agent-browser-source
for skill in core dogfood derive-client; do
  cp -a "/tmp/agent-browser-source/skill-data/$skill" /opt/agent-browser-skills/
done
cp /tmp/agent-browser-source/LICENSE /usr/local/share/licenses/agent-browser/LICENSE
rm -rf /tmp/node.tar.xz /tmp/agent-browser.tar.gz /tmp/agent-browser-source
