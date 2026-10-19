# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
ARG UBUNTU_IMAGE=ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
FROM ${UBUNTU_IMAGE} AS assets
ARG TARGETARCH
ARG APT_REFRESH
RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*
COPY downloads.env install-assets.sh /build/
RUN sh /build/install-assets.sh "$TARGETARCH"

FROM assets AS browser
ENV PATH=/opt/node/bin:$PATH PLAYWRIGHT_BROWSERS_PATH=/opt/playwright
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts && node node_modules/playwright/cli.js install --only-shell chromium

FROM ${UBUNTU_IMAGE} AS runtime
ARG APT_REFRESH
ARG IMAGE_VERSION=0.2.0
ARG SOURCE_REVISION
LABEL org.opencontainers.image.source="https://github.com/ClosyTalk/sandbox-image" \
      org.opencontainers.image.title="ClosyTalk agent sandbox" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${SOURCE_REVISION}" \
      keep-on-prune="true"
ENV PATH=/opt/venv/bin:$PATH \
    LANG=C.UTF-8 \
    MPLBACKEND=Agg \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    AGENT_BROWSER_EXECUTABLE_PATH=/usr/local/bin/chromium \
    AGENT_BROWSER_SKILLS_DIR=/opt/agent-browser-skills \
    AGENT_BROWSER_CONTENT_BOUNDARIES=1 \
    AGENT_BROWSER_MAX_OUTPUT=50000 \
    AGENT_BROWSER_CONFIRM_ACTIONS=eval,download \
    AGENT_BROWSER_DOWNLOAD_PATH=/tmp/downloads \
    AGENT_BROWSER_IDLE_TIMEOUT_MS=300000
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    ca-certificates python3 python3-venv poppler-utils fontconfig ffmpeg \
    fonts-liberation fonts-crosextra-carlito fonts-dejavu-core fonts-noto-core \
    fonts-noto-color-emoji \
    libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 libatspi2.0-0t64 \
    libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 \
    libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
    libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
    && rm -rf /var/lib/apt/lists/*
# Chromium's headless dependencies from the pinned playwright-core 1.64.0.
# Its install-deps also adds Xvfb and desktop fonts, which are not needed here.
# npm and Corepack are build tools; only Node itself belongs in the agent runtime.
COPY --from=assets /opt/node/bin/node /usr/local/bin/node
COPY --from=assets /opt/node/LICENSE /usr/local/share/licenses/node/LICENSE
COPY requirements.txt /usr/local/share/sandbox/requirements.txt
RUN python3 -m venv /opt/venv \
    && pip install --no-cache-dir --require-hashes --only-binary=:all: -r /usr/local/share/sandbox/requirements.txt \
    && pip check
# Headless Shell excludes the proprietary Widevine CDM bundled with full Chrome for Testing.
COPY --from=browser /opt/playwright/chromium_headless_shell-1248 /opt/chromium
COPY --from=assets /usr/local/bin/agent-browser /usr/local/bin/agent-browser
COPY --from=assets /opt/agent-browser-skills /opt/agent-browser-skills
COPY --from=assets /usr/local/share/licenses/agent-browser /usr/local/share/licenses/agent-browser
RUN chrome="$(find /opt/chromium -type f -name chrome-headless-shell -print -quit)" \
    && test -n "$chrome" && ln -s "$chrome" /usr/local/bin/chromium \
    && groupadd --gid 10001 sandbox && useradd --uid 10001 --gid sandbox --create-home sandbox \
    && mkdir -p /opt/skill /opt/skills /tmp/downloads \
    && chown sandbox:sandbox /opt/skill /opt/skills /tmp/downloads \
    && dpkg-query -W -f='${Package}\t${Version}\n' > /usr/local/share/sandbox/os-packages.tsv \
    && fc-cache -f
USER sandbox
WORKDIR /tmp
CMD ["/bin/sh"]
