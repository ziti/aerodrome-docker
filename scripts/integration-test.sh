#!/bin/sh

set -eu

project_name="aerodrome-test-${GITHUB_RUN_ID:-local}-$$"
export AERODROME_HOST_PORT="${AERODROME_HOST_PORT:-0}"

compose() {
    docker compose --project-name "$project_name" "$@"
}

diagnostics() {
    compose ps || true
    compose logs --no-color || true
}

cleanup() {
    exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        diagnostics
    fi
    compose down --volumes --remove-orphans >/dev/null 2>&1 || true
    exit "$exit_code"
}

wait_until_healthy() {
    attempts=60

    while [ "$attempts" -gt 0 ]; do
        container_id=$(compose ps --quiet aerodrome)
        if [ -n "$container_id" ]; then
            health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container_id")
            case "$health" in
                healthy)
                    return 0
                    ;;
                unhealthy)
                    echo "Aerodrome became unhealthy." >&2
                    return 1
                    ;;
            esac
        fi

        attempts=$((attempts - 1))
        sleep 2
    done

    echo "Timed out waiting for Aerodrome to become healthy." >&2
    return 1
}

assert_runtime_is_pruned() {
    compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
        "import pathlib; root = pathlib.Path('/opt/aerodrome'); forbidden = [root / '.git', root / '.github', root / 'scripts', root / 'tools', root / 'requirements-dev.txt']; forbidden += list(root.glob('test_*.py')); assert not [str(path) for path in forbidden if path.exists()]; assert (root / 'LICENSE').is_file()"
    compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
        "import importlib.util, pathlib; assert importlib.util.find_spec('pip') is None; assert not (pathlib.Path('/opt/venv/bin/pip')).exists()"
}

trap cleanup EXIT INT TERM

echo "Building and starting project $project_name"
compose up --detach --build
wait_until_healthy

compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
    "import urllib.request; response = urllib.request.urlopen('http://127.0.0.1:8000/api/ready', timeout=5); assert response.status == 200"
compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
    "from pathlib import Path; data = Path('/data'); assert (data / 'config.yaml').is_file(); assert (data / 'aircraft_history.db').is_file(); (data / '.integration-volume-marker').write_text('persisted')"
assert_runtime_is_pruned

echo "Recreating the container to verify named-volume persistence"
compose up --detach --force-recreate --no-build aerodrome
wait_until_healthy

compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
    "from pathlib import Path; data = Path('/data'); assert (data / 'config.yaml').is_file(); assert (data / 'aircraft_history.db').is_file(); assert (data / '.integration-volume-marker').read_text() == 'persisted'"
compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
    "import urllib.request; response = urllib.request.urlopen('http://127.0.0.1:8000/api/ready', timeout=5); assert response.status == 200"

echo "Integration test passed"
