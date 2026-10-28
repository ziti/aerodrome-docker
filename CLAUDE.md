# aerodrome-docker

Unofficial Docker packaging for [Aerodrome](https://github.com/preston-peterson/aerodrome) (self-hosted ADS-B dashboard). Hosted on GitHub (`ziti/aerodrome-docker`), not Gitea: use `gh`, not `tea`.

## Version
The Aerodrome release lives only in `ARG AERODROME_REF` in `Dockerfile`. Don't copy it anywhere else (compose and README deliberately don't). Renovate (hosted GitHub App, `renovate.json`) opens a weekly PR bumping it.

## Build and test
- `docker compose config --quiet`, `shellcheck scripts/*.sh`, `hadolint Dockerfile`
- `./scripts/integration-test.sh` builds the stack, waits for healthy, checks `/api/ready`, non-root, `/api/version` equals the Dockerfile pin, pruned runtime, and volume persistence across recreate.
- Base images come from `dhi.io` (Docker Hardened Images): `docker login dhi.io` first. CI uses secrets `DHI_USERNAME` / `DHI_TOKEN`.

## CI (`.github/workflows/ci.yml`)
`validate` (lint, compose, Renovate config) and `integration` (build, Trivy scan failing on fixable HIGH/CRITICAL, integration test). The integration job is skipped for fork PRs because it needs the secrets. Actions are pinned to SHAs; Renovate updates them.

## Gotchas
- Base-image (`dhi.io`) updates are not automated: hosted Renovate can't log in. Bump the tags in `Dockerfile` by hand.
- Don't use Aerodrome's in-app updater; upgrades are image rebuilds.
