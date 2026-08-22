# Aerodrome Docker

Unofficial Docker and Docker Compose support for [Aerodrome](https://github.com/preston-peterson/aerodrome), a self-hosted ADS-B dashboard for tracking and exploring aircraft seen by your local receiver.

This project packages Aerodrome into a container-friendly deployment while keeping the application itself as close to upstream as possible.

> This repository is not affiliated with or maintained by the Aerodrome project.

## Features

* Dockerized Aerodrome deployment
* Docker Compose configuration
* Persistent SQLite database storage
* Persistent Aerodrome configuration
* Health checking
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
git clone https://github.com/YOUR_USERNAME/aerodrome-docker.git
cd aerodrome-docker
```

Create the persistent data directory:

```bash
mkdir -p data
```

Download the upstream example configuration:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/preston-peterson/aerodrome/main/config.yaml.example \
  -o config.yaml
```

Edit `config.yaml` and configure your ADS-B receiver:

```yaml
receiver:
  ip: "192.168.1.100"
  port: 8080
  path: "/data/aircraft.json"
  poll_interval: 60

  latitude: null
  longitude: null
  distance_unit: "nmi"

web:
  host: "0.0.0.0"
  port: 8000

data:
  db_file: "/opt/aerodrome/data/aircraft_history.db"
```

The `data.db_file` setting should remain under `/opt/aerodrome/data` so the SQLite database is stored in the persistent Docker volume.

Build and start Aerodrome:

```bash
docker compose up -d --build
```

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
    hostname: aerodrome

    restart: unless-stopped

    ports:
      - "8000:8000"

    environment:
      TZ: America/Chicago

    volumes:
      - ./config.yaml:/opt/aerodrome/config.yaml
      - ./data:/opt/aerodrome/data

    command:
      - python3
      - main.py
      - start

    healthcheck:
      test:
        [
          "CMD",
          "python3",
          "-c",
          "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/', timeout=5)"
        ]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

    stop_grace_period: 30s
```

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

Aerodrome's configuration is stored in:

```text
./config.yaml
```

The file is bind-mounted into the container at:

```text
/opt/aerodrome/config.yaml
```

Aerodrome may update this file when configuration changes are made through its web interface, so it must be writable by the container.

## Persistent Data

Aerodrome's SQLite database is stored in:

```text
./data/
```

with the recommended configuration:

```yaml
data:
  db_file: "/opt/aerodrome/data/aircraft_history.db"
```

Do not store the database in the container's application directory unless you are comfortable losing it when the container is recreated.

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

The persistent `config.yaml` and `data/` directory are not removed.

## Repository Layout

```text
aerodrome-docker/
├── Dockerfile
├── docker-compose.yml
├── config.yaml
├── data/
└── README.md
```

A suggested `.gitignore`:

```gitignore
data/
config.yaml.bak.*
```

If your `config.yaml` contains sensitive notification credentials or other secrets, you may also want to exclude it and provide a sanitized `config.yaml.example` instead.

## Building Manually

Build the image:

```bash
docker build \
  --build-arg AERODROME_REF=v3.4.123 \
  -t aerodrome:local .
```

Run it:

```bash
docker run -d \
  --name aerodrome \
  --restart unless-stopped \
  -p 8000:8000 \
  -v "$PWD/config.yaml:/opt/aerodrome/config.yaml" \
  -v "$PWD/data:/opt/aerodrome/data" \
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
