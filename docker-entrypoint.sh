#!/bin/sh
set -e

if [ ! -f /data/config.yaml ]; then
    cp /opt/aerodrome/config.yaml.example /data/config.yaml

    sed -i \
        's|db_file: "aircraft_history.db"|db_file: "/data/aircraft_history.db"|' \
        /data/config.yaml
fi

ln -sf /data/config.yaml /opt/aerodrome/config.yaml

exec "$@"