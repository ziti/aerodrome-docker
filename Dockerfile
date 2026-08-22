FROM python:3.14-slim-trixie AS builder

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
        -r /build/aerodrome/requirements.txt


FROM dhi.io/python:3.14-debian13

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /build/aerodrome /opt/aerodrome

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /opt/aerodrome

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["python", "main.py", "start"]