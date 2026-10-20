# AGENTS.md — ClosyTalk sandbox images

This public repository builds the agent environment and OpenSandbox execd from
pinned upstream source. Platform and Shipyard consume their immutable GHCR references.

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
- For execd, pin the upstream repository, full source commit SHA and archive
  checksum in `Dockerfile.execd`. Preserve the upstream binary version string;
  `EXECD_VERSION` is the independently versioned ClosyTalk image release. Update
  its Dockerfile default, image labels and `test-execd.sh` checks together. Use a
  new patch release for compatible security fixes; never overwrite a published tag.
- Build execd with the latest patched stable Go release, with its builder image
  pinned by digest. Use `go get` and `go mod tidy` for the minimum module versions
  fixing reviewed advisories, accepting only their required transitive upgrades.
  Run upstream `go test ./...` and `go vet ./...` in both execd and the shared
  internal module on each architecture before building static Linux binaries.
  Install test prerequisites only in the builder. `execd-tests.patch` corrects
  the upstream test that assumes arm64 has the legacy `open` syscall: it uses
  `openat` and retains all filtering assertions. Do not skip tests or patch
  production source to bypass failures.
  Keep upstream ldflags and `-trimpath`; do not ship Windows binaries or the
  unused supervisor. Preserve runtime paths, scripts, entrypoint, user, env and
  permissions. The unchanged static bubblewrap is the only asset copied from
  the digest-pinned upstream image; verify its checksum on both architectures.
  Record the source repository, commit and Go version in image labels.
- Weekly workflows rebuild with refreshed Ubuntu/Alpine packages and rescan the
  images. They **do not advance pinned upstream commits, Go versions, modules,
  or image digests**. Advance those pins only in a reviewed pull request. Execd
  uses `apk upgrade --no-cache`; refresh its layer with `APK_REFRESH`. APT/APK
  packages are resolved at build time, so source rebuilds need not be byte-identical;
  the published image digest identifies the tested artifact.

## Required validation

- Both native architecture jobs must pass offline checks, Trivy scanning,
  SBOM generation and, for publication, signature verification. Preserve
  provenance, SBOMs and full vulnerability reports.
- `CRITICAL` is the existing blocking gate. Review `HIGH` and other findings
  in the PR, including upstream fixes and applicability. Do not lower the
  gate, suppress findings, or skip an architecture to make an update pass.
- `security.yml` runs on every PR and nightly. OSV-Scanner gates
  `requirements.txt` and `package-lock.json` on `CRITICAL`; zizmor fails on
  any unsuppressed workflow finding; Trivy rescans the three most recent stable
  releases of each image by digest on both architectures with the same gate.
  A red nightly on a published image means its consumers are exposed until a
  patched release or rebuild is rolled out. Scanners run as digest-pinned
  containers without capabilities, root, docker socket or credentials.
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
| execd source build | `EXECD_VERSION` | `execd-vX.Y.Z` | `execd-X.Y.Z` |

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
source, artifacts and logs. Callers pass the variable through a reusable
workflow secret parameter so masking is active before step metadata is logged;
do not inject an unmasked variable directly into step `env`, `with` or `run`.
Variables remain available to repository workflows: parameter masking is not
repository-wide access control and does not turn the stored variable into a secret.
Notify only from `main` or validated tag pushes, using a separate job and JSON
artifacts. PRs/forks and manual runs on arbitrary tags must not send messages.
