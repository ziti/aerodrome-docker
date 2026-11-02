ARG AERODROME_REF=v3.4.151

FROM dhi.io/python:3.14-debian13-dev AS builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Declared here so a version bump reuses the apt layer above.
ARG AERODROME_REF

RUN git clone \
    --depth 1 \
    --branch "${AERODROME_REF}" \
    https://github.com/preston-peterson/aerodrome.git \
    /build/aerodrome

COPY requirements.lock /build/requirements.lock

# Installs only hash-checked packages, then confirms they satisfy this release.
RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install \
        --no-cache-dir \
        --require-hashes \
        -r /build/requirements.lock \
    && { /opt/venv/bin/pip install \
            --no-index \
            --dry-run \
            --quiet \
            -r /build/aerodrome/requirements.txt \
        || { echo "requirements.lock does not satisfy this Aerodrome release. Run scripts/update-lock.sh." >&2; exit 1; }; } \
    && /opt/venv/bin/pip check \
    && /opt/venv/bin/python -m pip uninstall --yes pip \
    && rm -rf \
        /build/aerodrome/.git \
        /build/aerodrome/.github \
        /build/aerodrome/__pycache__ \
        /build/aerodrome/logs \
        /build/aerodrome/scripts \
        /build/aerodrome/tools \
        /build/aerodrome/update \
        /build/aerodrome/requirements-dev.txt \
        /build/aerodrome/bump-version.sh \
        /build/aerodrome/uninstall.sh \
        /build/aerodrome/.pii-allowlist \
        /build/aerodrome/.tracker.pid \
    && find /build/aerodrome -maxdepth 1 -type f -name 'test_*.py' -delete \
    && mkdir -p /build/volume-seed \
    && : > /build/volume-seed/.volume-initialized


FROM dhi.io/python:3.14-debian13

ARG AERODROME_REF

COPY --chown=65532:65532 --from=builder /opt/venv /opt/venv
COPY --chown=65532:65532 --from=builder /build/aerodrome /opt/aerodrome

COPY --chown=65532:65532 docker-entrypoint.py /usr/local/bin/docker-entrypoint.py
COPY --chown=65532:65532 --from=builder /build/volume-seed/ /data/

VOLUME /data

ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /opt/aerodrome

LABEL org.opencontainers.image.title="Aerodrome" \
      org.opencontainers.image.description="Unofficial container packaging for Aerodrome, a self-hosted ADS-B dashboard" \
      org.opencontainers.image.version="${AERODROME_REF}" \
      org.opencontainers.image.source="https://github.com/ziti/aerodrome-docker" \
      org.opencontainers.image.licenses="MIT"

HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=30s \
    CMD ["/opt/venv/bin/python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/ready', timeout=5)"]

ENTRYPOINT ["/opt/venv/bin/python3", "/usr/local/bin/docker-entrypoint.py"]
CMD ["python3", "main.py", "start"]
