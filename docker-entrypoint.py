import os
import sys
import tempfile
from pathlib import Path


DATA_DIR = Path("/data")
APP_DIR = Path("/opt/aerodrome")
CONFIG_PATH = DATA_DIR / "config.yaml"
DATABASE_PATH = DATA_DIR / "aircraft_history.db"
BACKUPS_PATH = DATA_DIR / ".backups"
DEFAULT_CONFIG_PATH = APP_DIR / "config.yaml.example"
DEFAULT_DB_SETTING = 'db_file: "aircraft_history.db"'
LOG_PATH = APP_DIR / "logs" / "tracker.log"
LOG_MAX_BYTES = 50 * 1024 * 1024
LOG_KEEP_BYTES = 10 * 1024 * 1024


def create_default_config() -> None:
    example = DEFAULT_CONFIG_PATH.read_text()
    if DEFAULT_DB_SETTING not in example:
        sys.exit(
            f"Cannot create {CONFIG_PATH}: {DEFAULT_CONFIG_PATH} no longer contains "
            f"'{DEFAULT_DB_SETTING}', so the database would not be stored in {DATA_DIR}."
        )
    config = example.replace(DEFAULT_DB_SETTING, f'db_file: "{DATABASE_PATH}"')

    descriptor, temporary = tempfile.mkstemp(dir=DATA_DIR, prefix=".config.yaml.")
    with os.fdopen(descriptor, "w") as temporary_file:
        temporary_file.write(config)
        temporary_file.flush()
        os.fsync(temporary_file.fileno())
    os.replace(temporary, CONFIG_PATH)


def link_into_app(name: str, target: Path) -> None:
    link = APP_DIR / name
    link.unlink(missing_ok=True)
    link.symlink_to(target)


def trim_log() -> None:
    """Aerodrome's log has no rotation, so limit it at each start."""
    try:
        size = LOG_PATH.stat().st_size
    except FileNotFoundError:
        return
    if size <= LOG_MAX_BYTES:
        return

    with LOG_PATH.open("rb") as log:
        log.seek(-LOG_KEEP_BYTES, os.SEEK_END)
        log.readline()  # Drop the partial first line.
        kept = log.read()
    temporary = LOG_PATH.with_name(f"{LOG_PATH.name}.trim")
    temporary.write_bytes(kept)
    os.replace(temporary, LOG_PATH)


def main() -> None:
    if not CONFIG_PATH.exists():
        create_default_config()

    BACKUPS_PATH.mkdir(mode=0o700, exist_ok=True)
    link_into_app("config.yaml", CONFIG_PATH)
    link_into_app(".backups", BACKUPS_PATH)
    trim_log()

    os.execvp(sys.argv[1], sys.argv[1:])


if __name__ == "__main__":
    main()
