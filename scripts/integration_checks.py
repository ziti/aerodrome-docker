"""Checks run inside the container by integration-test.sh.

The runtime image has no shell, so the test pipes this file to the container's
Python: `python3 - <command> [args...] < scripts/integration_checks.py`.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request

BASE_URL = "http://127.0.0.1:8000"
APP_CONFIG = "/opt/aerodrome/config.yaml"
DATA_CONFIG = "/data/config.yaml"
BACKUP_ZIP = "/data/.integration-backup.zip"
BOUNDARY = "integrationbackupboundary"
BACKUPS_LINK = "/opt/aerodrome/.backups"
BACKUPS_DIR = "/data/.backups"
LOG_FILE = "/opt/aerodrome/logs/tracker.log"
LOG_MARKER = b"integration-log-tail-marker"
APP_DIR = "/opt/aerodrome"
# Everything the image is expected to ship, and what Aerodrome creates at runtime.
# A new upstream entry fails the test, so someone decides whether to prune it.
KNOWN_APP_ENTRIES = {
    ".gitignore",
    ".gitattributes",
    "API.md",
    "ARCHITECTURE.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "DEVELOPMENT.md",
    "LICENSE",
    "README.md",
    "SECURITY.md",
    "VERSION",
    "config.yaml.example",
    "docs",
    "install.sh",
    "requirements.txt",
    "static",
    "templates",
    ".backups",
    ".tracker.pid",
    "__pycache__",
    "config.yaml",
    "logs",
}


def request(method, path, body=None, headers=None):
    req = urllib.request.Request(
        BASE_URL + path, data=body, method=method, headers=headers or {}
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def get_json(path):
    status, body = request("GET", path)
    assert status == 200, f"GET {path} returned {status}: {body[:300]!r}"
    return json.loads(body)


def maintenance_status():
    return get_json("/api/maintenance/status")


def set_receiver(address):
    config = get_json("/api/config")
    config["receiver"]["ip"] = address
    status, body = request(
        "PUT",
        "/api/config",
        json.dumps({"config": config}).encode(),
        {"Content-Type": "application/json"},
    )
    assert status == 200, f"settings save returned {status}: {body[:300]!r}"


def assert_receiver(address):
    running = get_json("/api/config")["receiver"]["ip"]
    assert running == address, f"running config has {running}, expected {address}"
    with open(DATA_CONFIG, encoding="utf-8") as config_file:
        saved = config_file.read()
    assert f'ip: "{address}"' in saved, f"{DATA_CONFIG} does not have {address}"


def assert_config_layout():
    assert os.path.islink(APP_CONFIG), f"{APP_CONFIG} is no longer a symlink"
    target = os.readlink(APP_CONFIG)
    assert target == DATA_CONFIG, f"{APP_CONFIG} points to {target}"
    assert not os.path.islink(DATA_CONFIG), f"{DATA_CONFIG} should be a regular file"
    mode = os.stat(DATA_CONFIG).st_mode & 0o777
    assert mode == 0o600, f"{DATA_CONFIG} has mode {mode:04o}, expected 0600"


def export_backup():
    status, body = request("GET", "/api/backup/export")
    assert status == 200, f"backup export returned {status}: {body[:300]!r}"
    with open(BACKUP_ZIP, "wb") as backup:
        backup.write(body)


def import_backup():
    with open(BACKUP_ZIP, "rb") as backup:
        payload = backup.read()
    body = (
        f"--{BOUNDARY}\r\n"
        'Content-Disposition: form-data; name="file"; filename="backup.zip"\r\n'
        "Content-Type: application/zip\r\n\r\n"
    ).encode()
    body += payload + f"\r\n--{BOUNDARY}--\r\n".encode()
    status, response = request(
        "POST",
        "/api/backup/import",
        body,
        {"Content-Type": f"multipart/form-data; boundary={BOUNDARY}"},
    )
    assert status == 200, f"backup import returned {status}: {response[:300]!r}"
    assert json.loads(response).get("staged") is True, "backup was not staged"


def assert_restore_pending():
    pending = maintenance_status()["restore"]["pending"]
    assert pending, "expected a restore waiting for its restart"


def assert_restore_succeeded():
    restore = maintenance_status()["restore"]
    assert restore["pending"] is None, f"restore still pending: {restore['pending']}"
    assert restore["result"] and restore["result"].get("ok") is True, (
        f"restore did not succeed: {restore['result']}"
    )


def assert_restore_not_applied():
    restore = maintenance_status()["restore"]
    assert restore["pending"] is None, f"restore still pending: {restore['pending']}"
    assert restore["result"] and restore["result"].get("ok") is False, (
        f"expected a restore that was not applied, got {restore['result']}"
    )


def assert_backups_on_volume():
    assert os.path.islink(BACKUPS_LINK), f"{BACKUPS_LINK} is not a symlink"
    target = os.readlink(BACKUPS_LINK)
    assert target == BACKUPS_DIR, f"{BACKUPS_LINK} points to {target}"
    mode = os.stat(BACKUPS_DIR).st_mode & 0o777
    assert mode == 0o700, f"{BACKUPS_DIR} has mode {mode:04o}, expected 0700"
    last_good = os.path.join(BACKUPS_DIR, "config.yaml.last-good")
    assert os.path.isfile(last_good), f"{last_good} is missing"


def assert_known_app_files():
    unknown = sorted(
        name
        for name in os.listdir(APP_DIR)
        if name not in KNOWN_APP_ENTRIES and not re.fullmatch(r"\w+\.py", name)
    )
    assert not unknown, (
        f"new entries in {APP_DIR}: {unknown}. Prune them in the Dockerfile or add "
        "them to KNOWN_APP_ENTRIES."
    )


def grow_log():
    with open(LOG_FILE, "ab") as log:
        log.truncate(60 * 1024 * 1024)
        log.seek(0, os.SEEK_END)
        log.write(b"\n" + LOG_MARKER + b"\n")


def assert_log_trimmed():
    size = os.path.getsize(LOG_FILE)
    assert size < 20 * 1024 * 1024, f"{LOG_FILE} is still {size} bytes"
    with open(LOG_FILE, "rb") as log:
        assert LOG_MARKER in log.read(), "the end of the log was not kept"


def break_config():
    with open(DATA_CONFIG, "w", encoding="utf-8") as config_file:
        config_file.write("web: [unclosed\n")


def assert_config_recovered():
    notice = maintenance_status()["config"]
    assert notice and notice.get("kind") == "unreadable", (
        f"expected a config recovery notice, got {notice}"
    )
    assert notice.get("broken_copy"), f"broken config was not kept: {notice}"


def show_state():
    print(json.dumps(maintenance_status(), indent=2))
    for directory in ("/data", BACKUPS_LINK):
        print(directory, sorted(os.listdir(directory)))
    print(
        "/opt/aerodrome config files",
        sorted(n for n in os.listdir("/opt/aerodrome") if "config.yaml" in n),
    )


COMMANDS = {
    "set-receiver": set_receiver,
    "assert-receiver": assert_receiver,
    "assert-config-layout": assert_config_layout,
    "export-backup": export_backup,
    "import-backup": import_backup,
    "assert-restore-pending": assert_restore_pending,
    "assert-restore-succeeded": assert_restore_succeeded,
    "assert-restore-not-applied": assert_restore_not_applied,
    "assert-backups-on-volume": assert_backups_on_volume,
    "assert-known-app-files": assert_known_app_files,
    "grow-log": grow_log,
    "assert-log-trimmed": assert_log_trimmed,
    "break-config": break_config,
    "assert-config-recovered": assert_config_recovered,
    "show-state": show_state,
}


if __name__ == "__main__":
    COMMANDS[sys.argv[1]](*sys.argv[2:])
