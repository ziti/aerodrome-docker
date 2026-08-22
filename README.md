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

    container_name: aerodrome
    restart: unless-stopped

    ports:
      - "8000:8000"

    environment:
      TZ: America/Chicago

    volumes:
      - aerodrome-data:/data

    command:
      - python3
      - main.py
      - start

volumes:
  aerodrome-data:
```

## Dockhand Deployment

This repository can be deployed as a Git-backed Dockhand stack. Enable **Build images on deploy** and deploy the repository; no container registry is required. The Compose-defined `aerodrome-data` named volume retains Aerodrome's configuration and SQLite database across normal redeployments.

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

The image uses a multi-stage build and a minimal non-root hardened runtime image. Build-only tooling, including Git, remains in the builder stage; it is not included in the runtime image.

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

## Repository Layout

```text
aerodrome-docker/
├── Dockerfile
├── docker-compose.yml
├── docker-entrypoint.sh
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
