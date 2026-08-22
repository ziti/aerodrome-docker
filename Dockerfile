FROM dhi.io/python:3.14-debian13

ARG AERODROME_REF=v3.4.123

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone \
        --depth 1 \
        --branch "${AERODROME_REF}" \
        https://github.com/preston-peterson/aerodrome.git \
        /opt/aerodrome

WORKDIR /opt/aerodrome

RUN pip install \
    --no-cache-dir \
    --disable-pip-version-check \
    -r requirements.txt

RUN mkdir -p /data

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["python3", "main.py", "start"]
