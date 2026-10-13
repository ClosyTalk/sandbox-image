# AGENTS.md — ClosyTalk sandbox images

This public repository builds the agent environment and mirrors OpenSandbox
execd. Platform and Shipyard consume their immutable GHCR references.

## Update policy

- Submit changes through a pull request into `main`. Do not push to `main`,
  merge, tag, or publish without authorization in the current conversation.
- Review upstream releases and advisories when reviewing the weekly scan.
  Security fixes take priority over routine upgrades; review compatibility
  before updating a consumer's image reference.
- Keep base images, downloaded binaries and GitHub Actions pinned by digest
  or full commit SHA. Verify binary checksums against official upstream
  release metadata for **both amd64 and arm64**.
- Python dependencies belong in `requirements.in`; regenerate the fully
  pinned, hashed `requirements.txt`. Keep wheel-only, hash-checked installs.
  Update Playwright through `package.json` and `package-lock.json` together.
- Node and agent-browser versions and architecture checksums live in
  `downloads.env`. When updating Playwright, also update the Chromium revision
  copied in `Dockerfile` and check its runtime libraries.
- For execd, update `EXECD_VERSION`, the upstream version and manifest digest
  in `Dockerfile.execd`, and its base-image labels together. Preserve upstream
  runtime behavior: this mirror adds image metadata and prune protection.
- Weekly workflows rebuild with refreshed Ubuntu packages and rescan the
  images. They **do not advance pinned upstream versions**. An execd rebuild
  from the same pinned base cannot fix a vulnerability inside that base.
  APT packages are resolved at build time, so source rebuilds need not be
  byte-identical; the published image digest identifies the tested artifact.

## Required validation

- Both native architecture jobs must pass offline checks, Trivy scanning,
  SBOM generation and, for publication, signature verification. Preserve
  provenance, SBOMs and full vulnerability reports.
- `CRITICAL` is the existing blocking gate. Review `HIGH` and other findings
  in the PR, including upstream fixes and applicability. Do not lower the
  gate, suppress findings, or skip an architecture to make an update pass.
- Trivy's report alone does not prove vendored Node, Chromium or agent-browser
  binaries are free of vulnerabilities. Review their official advisories
  when changing versions and record relevant findings in the PR.
- Keep the agent image non-root, with no installation or download required
  at runtime. Preserve workspace compatibility and `keep-on-prune=true` on
  both images. Test changes to tools or browser behavior offline on both
  architectures. Test execd workspace operations without following symlinks.
- Run notification tests with
  `python3 -m unittest discover -s .github/scripts -p 'test_*.py'`.
  Validate workflow syntax and security when editing `.github/workflows/`.
- The PR explains changed versions/digests, validation results, findings and
  any rollout requirement for Platform or Shipyard. Keep commits in English.

## Publication and rollout

| Image | Version file | Git release tag | GHCR tag |
|---|---|---|---|
| Agent sandbox | `VERSION` | `vX.Y.Z` | `X.Y.Z` |
| execd mirror | `EXECD_VERSION` | `execd-vX.Y.Z` | `execd-X.Y.Z` |

- Use patch versions for compatible fixes and upgrades, minor versions for
  added capabilities, and major versions for incompatible consumer changes.
  Cut release tags only on reviewed commits already present in `main`.
- Never move a published Git tag or overwrite a GHCR version tag. For a
  rebuild of the same pinned version, use the workflow on `main`; it creates
  a unique `-rebuild.DATE.RUN.ATTEMPT` prerelease. Do not reuse an old tag.
- Publish the exact OCI artifacts tested by the architecture jobs. Verify
  the signed release and anonymous pulls on both architectures before
  updating downstream references. Consumers should pin a version and digest.
- Publishing or rebuilding an image does not upgrade managed instances.
  Changes to Platform/Shipyard references and host rollout are separate work.

## Slack configuration

The notifier reads the existing organization Actions **variable**
`SLACK_DEVELOPMENT_CHANNEL_WEBHOOK_URL`, matching Platform. Grant repository
access through the organization's **Variables** tab. Keep its value out of
source, artifacts and logs; the posting step registers a log mask before use.
Variables are available to repository workflows and are not protected like
secrets: the posting-step mask is not repository-wide access control.
Notify only from `main` or validated tag pushes, using a separate job and JSON
artifacts. PRs/forks and manual runs on arbitrary tags must not send messages.
