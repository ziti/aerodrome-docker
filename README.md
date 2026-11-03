# Aerodrome Docker

Unofficial Docker and Docker Compose support for [Aerodrome](https://github.com/preston-peterson/aerodrome), a self-hosted ADS-B dashboard for tracking and exploring aircraft seen by your local receiver.

This project packages Aerodrome into a container-friendly deployment while keeping the application itself as close to upstream as possible.

> This repository is not affiliated with or maintained by the Aerodrome project.

## Features

* Dockerized Aerodrome deployment
* Docker Compose configuration
* Persistent SQLite database storage
* Persistent Aerodrome configuration
* Version pinning through a Docker build argument
* Works with any compatible `aircraft.json` source, including:

  * readsb
  * dump1090
  * tar1090
  * PiAware

## Requirements

* Docker Engine
* Docker Compose
* A free Docker account, used to pull the base images from `dhi.io` (Docker Hardened Images)
* An ADS-B receiver exposing an `aircraft.json` endpoint

## Quick Start

Log in to the registry that hosts the base images, then clone the repository and start it:

```bash
docker login dhi.io
git clone https://github.com/ziti/aerodrome-docker.git
cd aerodrome-docker
docker compose up -d --build
```

On first start, the container creates `/data/config.yaml` in the persistent `aerodrome-data` named volume. Configure your ADS-B receiver through the Aerodrome web interface, or edit that file as described in [Configuration](#configuration).

Open the dashboard:

```text
http://localhost:8000
```

Or replace `localhost` with the IP address or hostname of your Docker host.

## Security Notice

**Aerodrome has no login.** Anyone who can reach its port can read and change its settings, download a backup of its data, and use its in-app update routes. Upstream designs it for a trusted local network.

By default this Compose file publishes the port on all of the host's network interfaces. Docker's published ports can also bypass host firewall rules such as `ufw`. Do not expose it directly to the internet or an untrusted network. To limit access, either:

* Set `AERODROME_BIND_ADDRESS=127.0.0.1` so that only the Docker host can reach it, or
* Put it behind a VPN or a reverse proxy that handles authentication. See [Reverse Proxy](#reverse-proxy).

## Docker Compose

[docker-compose.yml](docker-compose.yml) persists Aerodrome's configuration and database in the `aerodrome-data` named volume. It reads these optional environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `AERODROME_BIND_ADDRESS` | `0.0.0.0` | Host address the port is published on |
| `AERODROME_HOST_PORT` | `8000` | Host port |
| `AERODROME_MEM_LIMIT` | `0` (no limit) | Container memory limit, such as `1g`. Memory use grows with the database, so choose a limit for your data. |

Compose assigns the container and volume names from the Compose project name, so independent stacks do not collide. To run parallel stacks on one host, give each a different project name and host port:

```bash
AERODROME_HOST_PORT=8001 docker compose --project-name aerodrome-lab up -d --build
```

The image's healthcheck reports whether `/api/ready` is responsive. Docker marks a failed check as `unhealthy`, but `restart: unless-stopped` only restarts a container after its process exits; it does not restart an unhealthy process. Use a health-aware monitor if automatic remediation of an unhealthy-but-running process is required.

## Reverse Proxy

Aerodrome refuses requests with a `Host` header it does not recognize, and answers with HTTP 403. If you serve it from a public-style hostname, add that hostname to `allowed_hosts` under `web` in `/data/config.yaml`:

```yaml
web:
  allowed_hosts: "aerodrome.example.com"
```

Separate multiple hostnames with commas. Aerodrome has no login of its own, so add authentication at the proxy if anyone untrusted can reach it.

## Version Pinning

The Aerodrome release built into the image is set in one place: the `AERODROME_REF` argument at the top of the [Dockerfile](Dockerfile), with its commit beside it. Compose uses that default, so there is nothing else to edit.

Python dependencies are installed only from [requirements.lock](requirements.lock), with hash checking, so a rebuild installs the same packages. If a different release needs packages the lock does not satisfy, the build stops and tells you to run `scripts/update-lock.sh`.

The Dockerfile also pins that release's commit in `AERODROME_COMMIT`, and the build fails if the tag points anywhere else. To build a different release without changing the file, override both at build time:

```bash
docker compose build \
  --build-arg AERODROME_REF=<release-tag> \
  --build-arg AERODROME_COMMIT=<commit-sha>
```

Find a tag's commit with `git ls-remote https://github.com/preston-peterson/aerodrome.git '<release-tag>^{}' '<release-tag>'`. If it prints two lines, use the one ending in `^{}`.

### Automated upgrades

[Renovate](https://docs.renovatebot.com/) checks Aerodrome's GitHub releases once a week (see [renovate.json](renovate.json)) and opens a pull request that changes `AERODROME_REF`, once a release is at least three days old. It also opens grouped pull requests for `requirements.lock`. CI then builds the image, scans it, and runs the integration test, including a check that the running app reports the pinned version. Merge the pull request, then rebuild and redeploy:

```bash
docker compose build --pull
docker compose up -d
```

This deployment intentionally treats the container image as the application lifecycle boundary.

## Updating

Aerodrome's native installation is designed around systemd and includes its own update and restart mechanisms.

Those host-level operations do not map cleanly to an immutable Docker deployment.

For this project, use Docker to manage:

* Aerodrome upgrades
* Rollbacks
* Restarts
* Container lifecycle

Avoid using Aerodrome's in-application updater when running this image.

## Configuration

Aerodrome's configuration is stored in the `aerodrome-data` named volume at:

```text
/data/config.yaml
```

The entrypoint symlinks that file to Aerodrome's expected path:

```text
/opt/aerodrome/config.yaml
```

The entrypoint creates `/data/config.yaml` from Aerodrome's upstream example on first start and changes its database setting to the persistent volume path. Aerodrome may update this file when configuration changes are made through its web interface, so it must remain writable by the container.

## Persistent Data

Aerodrome's SQLite database is stored in the `aerodrome-data` named volume:

```text
/data/aircraft_history.db
```

with the recommended configuration:

```yaml
data:
  db_file: "/data/aircraft_history.db"
```

Do not store the database in the container's application directory unless you are comfortable losing it when the container is recreated. The entrypoint configures this path automatically for a new volume.

Aerodrome's `.backups` folder is linked to `/data/.backups`, so its last known-good configuration survives a container recreate. Server-side backups and restore uploads therefore use space on the volume.

Automatic `config.yaml.bak.*` copies are still written to the container filesystem and are lost when the container is recreated.

## Image Security

The image uses a multi-stage build and a minimal non-root hardened runtime image. Build-only tooling, including Git and `pip`, remains in or is removed during the builder stage. The runtime copy excludes the upstream Git metadata, CI configuration, tests, development requirements, scripts, tools, logs, and update artifacts while retaining the files Aerodrome needs to run and the upstream license.

The Compose file drops all Linux capabilities, enables `no-new-privileges`, and limits the number of processes. Base images and Aerodrome's release are chosen in the [Dockerfile](Dockerfile), and a weekly CI job rebuilds and scans the image from scratch.

Base image updates are not automated. Rebuild with `docker compose build --pull` to pick up a newer image for the same tag, or change the tags in the Dockerfile.

## Health and Automated Testing

Check readiness and health with:

```bash
curl --fail http://localhost:8000/api/ready
docker compose ps
```

The integration test builds the image and starts an isolated Compose project. It checks readiness, runtime pruning, and persistence across a recreate, then tests settings saves, backup and restore, recovery from a broken configuration, log trimming, and an upgrade from the previous Aerodrome release:

```bash
./scripts/integration-test.sh
```

The test removes its own temporary project and volume when it finishes. GitHub Actions runs static validation and the integration test. Configure repository secrets named `DHI_USERNAME` and `DHI_TOKEN` so CI can pull the authenticated Docker Hardened Images base images. The integration job fails for pull requests from forks because GitHub does not expose repository secrets to them; a maintainer tests those changes from a branch in this repository.

## Backups

The named volume is persistent, not inherently backed up. Configure scheduled backups and perform restore drills before treating the deployment as durable. See [BACKUP.md](BACKUP.md) for what to back up, how to restore, data-loss scenarios, and restore verification.

## Logs

View Aerodrome logs with:

```bash
docker compose logs -f aerodrome
```

Docker's log size is controlled by your Docker daemon's log driver settings; this Compose file leaves them to you because a `logging:` block can conflict with or override a custom log driver. Aerodrome also writes `logs/tracker.log` inside the container. It is cut down at each container start once it passes 50 MiB, and it is removed when the container is recreated.

Check container status:

```bash
docker compose ps
```

## Stopping

```bash
docker compose down
```

`docker compose down` preserves the `aerodrome-data` named volume. In contrast, the following command permanently deletes Aerodrome's database and configuration:

```bash
docker compose down -v
```

Host loss, Docker volume pruning, corruption, operator error, and failed upgrades can also destroy or invalidate the data. A tested off-host backup is the recovery boundary.

## Repository Layout

```text
aerodrome-docker/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── scheduled-scan.yml
├── scripts/
│   ├── integration-test.sh
│   ├── integration_checks.py
│   └── update-lock.sh
├── .dockerignore
├── .gitignore
├── BACKUP.md
├── CLAUDE.md
├── Dockerfile
├── LICENSE
├── README.md
├── docker-compose.yml
├── docker-entrypoint.py
├── renovate.json
└── requirements.lock
```

## Building Manually

Build the image:

```bash
docker build -t aerodrome:local .
```

Run it:

```bash
docker volume create aerodrome-data

docker run -d \
  --name aerodrome \
  --restart unless-stopped \
  -p 8000:8000 \
  -v aerodrome-data:/data \
  aerodrome:local
```

## Upstream Project

Aerodrome is developed by Preston Peterson:

https://github.com/preston-peterson/aerodrome

Please report Aerodrome application bugs and feature requests to the upstream project when appropriate.

Issues specific to Docker packaging, Compose configuration, or this container image should be reported to this repository.

## License

This repository contains Docker packaging and deployment configuration for Aerodrome.

Aerodrome itself is licensed separately under the MIT License. See the upstream repository for its license and copyright information.
