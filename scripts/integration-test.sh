#!/bin/sh

set -eu

project_name="${AERODROME_TEST_PROJECT:-aerodrome-test-${GITHUB_RUN_ID:-local}-$$}"
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

assert_runs_as_non_root() {
    compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
        "import os; assert os.getuid() != 0, 'container runs as root'"
}

assert_running_version() {
    compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
        "import json, sys, urllib.request; version = json.load(urllib.request.urlopen('http://127.0.0.1:8000/api/version', timeout=5))['version']; assert version == sys.argv[1], f'running {version}, expected {sys.argv[1]}'" \
        "${1#v}"
}

assert_version_matches_pin() {
    expected=$(sed -n 's/^ARG AERODROME_REF=//p' Dockerfile)
    if [ -z "$expected" ]; then
        echo "Could not read AERODROME_REF from the Dockerfile." >&2
        return 1
    fi

    assert_running_version "$expected"
}

run_check() {
    compose exec --no-TTY aerodrome /opt/venv/bin/python3 - "$@" < scripts/integration_checks.py
}

recreate() {
    compose up --detach --force-recreate --no-build aerodrome
    wait_until_healthy
}

restart() {
    compose restart aerodrome
    wait_until_healthy
}

test_settings_save() {
    echo "Saving settings through the symlinked config"
    run_check assert-config-layout
    run_check set-receiver 192.0.2.77
    run_check assert-receiver 192.0.2.77
    run_check assert-config-layout
    recreate
    run_check assert-receiver 192.0.2.77
    run_check assert-config-layout
}

test_backup_restore() {
    echo "Restoring a backup, which the container finishes at its restart"
    run_check export-backup
    run_check set-receiver 192.0.2.88
    run_check import-backup
    run_check assert-restore-pending
    restart
    run_check assert-restore-succeeded
    run_check assert-receiver 192.0.2.77
    run_check assert-config-layout
}

test_recreate_during_restore() {
    echo "Recreating the container while a restore waits: current data must be kept"
    run_check set-receiver 192.0.2.99
    run_check import-backup
    run_check assert-restore-pending
    recreate
    run_check assert-restore-not-applied
    run_check assert-receiver 192.0.2.99
    run_check assert-config-layout
}

test_broken_config_recovery() {
    echo "Starting with an unreadable config: the last good one must be used"
    # The last good copy is written once a start can listen, so start cleanly first.
    restart
    run_check break-config
    restart
    run_check assert-config-recovered
    run_check assert-receiver 192.0.2.99
    run_check assert-config-layout

    echo "The last good config must also survive a recreate"
    run_check assert-backups-on-volume
    run_check break-config
    recreate
    run_check assert-config-recovered
    run_check assert-receiver 192.0.2.99
    run_check assert-config-layout
}

test_log_trim() {
    echo "Trimming an oversized log at start"
    run_check grow-log
    restart
    run_check assert-log-trimmed
}

test_image_metadata() {
    echo "Checking image metadata"
    container_id=$(compose ps --quiet aerodrome)
    mounts=$(docker inspect --format '{{range .Mounts}}{{.Destination}} {{end}}' "$container_id")
    case "$mounts" in
        */data*) ;;
        *)
            echo "/data is not a volume: $mounts" >&2
            return 1
            ;;
    esac

    image_id=$(docker inspect --format '{{.Image}}' "$container_id")
    declared=$(docker image inspect --format '{{json .Config.Volumes}}' "$image_id")
    case "$declared" in
        *'"/data"'*) ;;
        *)
            echo "The image does not declare /data as a volume: $declared" >&2
            return 1
            ;;
    esac

    pinned=$(sed -n 's/^ARG AERODROME_REF=//p' Dockerfile)
    label=$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$image_id")
    if [ "$label" != "$pinned" ]; then
        echo "Image version label is $label, expected $pinned" >&2
        return 1
    fi
}

previous_release() {
    pinned=$(sed -n 's/^ARG AERODROME_REF=//p' Dockerfile)
    git ls-remote --tags --refs https://github.com/preston-peterson/aerodrome.git 'v*' \
        | sed 's#.*refs/tags/##' \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | { cat; echo "$pinned"; } \
        | sort -u -V \
        | grep -B1 -x "$pinned" \
        | head -n 1
}

test_upgrade_from_previous_release() {
    previous=$(previous_release)
    pinned=$(sed -n 's/^ARG AERODROME_REF=//p' Dockerfile)
    if [ -z "$previous" ] || [ "$previous" = "$pinned" ]; then
        echo "Could not find the release before $pinned." >&2
        return 1
    fi

    echo "Upgrading a volume from $previous to $pinned"
    compose down --volumes --remove-orphans
    compose build --build-arg "AERODROME_REF=$previous"
    compose up --detach --no-build
    wait_until_healthy
    assert_running_version "$previous"
    run_check set-receiver 192.0.2.66

    compose build
    recreate
    assert_version_matches_pin
    run_check assert-receiver 192.0.2.66
    run_check assert-config-layout
    run_check set-receiver 192.0.2.67
    run_check assert-receiver 192.0.2.67
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
run_check assert-known-app-files
assert_runs_as_non_root
assert_version_matches_pin

echo "Recreating the container to verify named-volume persistence"
compose up --detach --force-recreate --no-build aerodrome
wait_until_healthy

compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
    "from pathlib import Path; data = Path('/data'); assert (data / 'config.yaml').is_file(); assert (data / 'aircraft_history.db').is_file(); assert (data / '.integration-volume-marker').read_text() == 'persisted'"
compose exec --no-TTY aerodrome /opt/venv/bin/python3 -c \
    "import urllib.request; response = urllib.request.urlopen('http://127.0.0.1:8000/api/ready', timeout=5); assert response.status == 200"

test_settings_save
test_backup_restore
test_recreate_during_restore
test_broken_config_recovery
test_log_trim
test_image_metadata
test_upgrade_from_previous_release

echo "Integration test passed"
