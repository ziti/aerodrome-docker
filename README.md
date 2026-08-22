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
* An ADS-B receiver exposing an `aircraft.json` endpoint

## Quick Start

Clone the repository:

```bash
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

## Docker Compose

The included Compose configuration persists the Aerodrome configuration and database:

```yaml
services:
  aerodrome:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        AERODROME_REF: v3.4.123

    restart: unless-stopped

    ports:
      - "${AERODROME_BIND_ADDRESS:-0.0.0.0}:${AERODROME_HOST_PORT:-8000}:8000"

    environment:
      TZ: America/Chicago

    volumes:
      - aerodrome-data:/data

    command:
      - python3
      - main.py
      - start

    healthcheck:
      test:
        - CMD
        - /opt/venv/bin/python3
        - -c
        - import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/ready', timeout=5)
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

volumes:
  aerodrome-data:
```

Compose assigns the container and volume names from the Compose project name, so independent stacks do not collide. To run parallel stacks on one host, give each a different project name and host port:

```bash
AERODROME_HOST_PORT=8001 docker compose --project-name aerodrome-lab up -d --build
```

The healthcheck reports whether `/api/ready` is responsive. Docker marks a failed check as `unhealthy`, but `restart: unless-stopped` only restarts a container after its process exits; it does not restart an unhealthy process. Use Dockhand or another health-aware monitor if automatic remediation of an unhealthy-but-running process is required.

## Dockhand Deployment

This repository can be deployed as a Git-backed Dockhand stack. Enable **Build images on deploy** and deploy the repository; no application image registry is required. The build environment must be able to authenticate to `dhi.io` for the Docker Hardened Images base images. The Compose-defined `aerodrome-data` named volume retains Aerodrome's configuration and SQLite database across normal redeployments.

## Version Pinning

Aerodrome can be pinned to a specific upstream release using the `AERODROME_REF` build argument:

```yaml
args:
  AERODROME_REF: v3.4.123
```

To upgrade:

1. Change `AERODROME_REF` to the desired Aerodrome release.
2. Rebuild the image.
3. Redeploy the container.

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

## Image Security

The image uses a multi-stage build and a minimal non-root hardened runtime image. Build-only tooling, including Git and `pip`, remains in or is removed during the builder stage. The runtime copy excludes the upstream Git metadata, CI configuration, tests, development requirements, scripts, tools, logs, and update artifacts while retaining the files Aerodrome needs to run and the upstream license.

## Health and Automated Testing

Check readiness and health with:

```bash
curl --fail http://localhost:8000/api/ready
docker compose ps
```

The integration test builds the image, starts an isolated Compose project, waits for `/api/ready`, verifies runtime pruning, recreates the container, and confirms that the configuration, SQLite database, and a test marker survived in the named volume:

```bash
./scripts/integration-test.sh
```

The test removes its own temporary project and volume when it finishes. GitHub Actions runs static validation and the integration test. Configure repository secrets named `DHI_USERNAME` and `DHI_TOKEN` so CI can pull the authenticated Docker Hardened Images base images. Integration tests are skipped for pull requests from forks because GitHub does not expose repository secrets to them.

## Backups

The named volume is persistent, not inherently backed up. Configure scheduled backups and perform restore drills before treating the deployment as durable. See [BACKUP.md](BACKUP.md) for the recommended Dockhand and Restic workflow, application-consistency guidance, data-loss scenarios, and restore verification.

## Logs

View Aerodrome logs with:

```bash
docker compose logs -f aerodrome
```

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
│       └── ci.yml
├── scripts/
│   └── integration-test.sh
├── BACKUP.md
├── Dockerfile
├── docker-compose.yml
├── docker-entrypoint.py
├── README.md
├── LICENSE
└── .gitignore
```

## Building Manually

Build the image:

```bash
docker build \
  --build-arg AERODROME_REF=v3.4.123 \
  -t aerodrome:local .
```

Run it:

```bash
docker volume create aerodrome-data

docker run -d \
  --name aerodrome \
  --restart unless-stopped \
  -p 8000:8000 \
  -v aerodrome-data:/data \
  --health-cmd "/opt/venv/bin/python3 -c \"import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/ready', timeout=5)\"" \
  --health-interval 10s \
  --health-timeout 5s \
  --health-retries 5 \
  --health-start-period 30s \
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
