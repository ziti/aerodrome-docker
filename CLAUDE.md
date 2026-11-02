# aerodrome-docker

Unofficial Docker packaging for [Aerodrome](https://github.com/preston-peterson/aerodrome) (self-hosted ADS-B dashboard). Hosted on GitHub (`ziti/aerodrome-docker`), not Gitea: use `gh`, not `tea`.

## Version
The Aerodrome release lives only in `ARG AERODROME_REF` in `Dockerfile`. Don't copy it anywhere else (compose and README deliberately don't). Renovate (hosted GitHub App, `renovate.json`) opens a weekly PR bumping it.

## Dependencies
The image installs only `requirements.lock` (hash-checked). Renovate updates it in one grouped PR. If the build says the lock doesn't satisfy a new Aerodrome release, run `scripts/update-lock.sh` on that branch and commit the result.

## Build and test
- `docker compose config --quiet`, `shellcheck scripts/*.sh`, `hadolint Dockerfile`
- `./scripts/integration-test.sh` builds the stack, waits for healthy, checks `/api/ready`, non-root, `/api/version` equals the Dockerfile pin, pruned runtime, and volume persistence across recreate; then settings saves, backup and restore (including a recreate while one waits), broken-config recovery, and an upgrade from the previous release. `scripts/integration_checks.py` holds the checks that run inside the container, which has no shell.
- Base images come from `dhi.io` (Docker Hardened Images): `docker login dhi.io` first. CI uses secrets `DHI_USERNAME` / `DHI_TOKEN`.

## CI (`.github/workflows/ci.yml`)
`validate` (lint, compose, Renovate config) and `integration` (integration test, then a Trivy scan of that image, failing on fixable HIGH/CRITICAL). The integration job fails on fork PRs because it needs the secrets; test them from a branch in this repo. `scheduled-scan.yml` runs a no-cache build and scan weekly; a failed run is the alert. Actions are pinned to SHAs (the repo requires it); Renovate updates them.

## Gotchas
- Base-image (`dhi.io`) updates are not automated: hosted Renovate can't log in. Bump the tags in `Dockerfile` by hand.
- Don't use Aerodrome's in-app updater; upgrades are image rebuilds.
