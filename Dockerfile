FROM dhi.io/python:3.14-debian13-dev AS builder

ARG AERODROME_REF=v3.4.123

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN git clone \
    --depth 1 \
    --branch "${AERODROME_REF}" \
    https://github.com/preston-peterson/aerodrome.git \
    /build/aerodrome

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install \
        --no-cache-dir \
        -r /build/aerodrome/requirements.txt \
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

COPY --chown=65532:65532 --from=builder /opt/venv /opt/venv
COPY --chown=65532:65532 --from=builder /build/aerodrome /opt/aerodrome

COPY --chown=65532:65532 docker-entrypoint.py /usr/local/bin/docker-entrypoint.py
COPY --chown=65532:65532 --from=builder /build/volume-seed/ /data/

ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /opt/aerodrome

ENTRYPOINT ["/opt/venv/bin/python3", "/usr/local/bin/docker-entrypoint.py"]
CMD ["python", "main.py", "start"]
