FROM python:3.12-slim

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

EXPOSE 8000

CMD ["python3", "main.py", "start"]