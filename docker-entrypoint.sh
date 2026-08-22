#!/bin/sh
set -e

if [ ! -f /data/config.yaml ]; then
    cp /opt/aerodrome/config.yaml.example /data/config.yaml
fi

ln -sf /data/config.yaml /opt/aerodrome/config.yaml

exec "$@"