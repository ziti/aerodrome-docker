import os
import shutil
import sys
from pathlib import Path


DATA_DIR = Path("/data")
CONFIG_PATH = DATA_DIR / "config.yaml"
APP_CONFIG_PATH = Path("/opt/aerodrome/config.yaml")
DEFAULT_CONFIG_PATH = Path("/opt/aerodrome/config.yaml.example")


def main() -> None:
    if not CONFIG_PATH.exists():
        shutil.copyfile(DEFAULT_CONFIG_PATH, CONFIG_PATH)
        CONFIG_PATH.write_text(
            CONFIG_PATH.read_text().replace(
                'db_file: "aircraft_history.db"',
                'db_file: "/data/aircraft_history.db"',
            )
        )

    APP_CONFIG_PATH.unlink(missing_ok=True)
    APP_CONFIG_PATH.symlink_to(CONFIG_PATH)

    os.execvp(sys.argv[1], sys.argv[1:])


if __name__ == "__main__":
    main()
