ARG base_image=ghcr.io/runatlantis/atlantis:v0.31.0
FROM ${base_image}

USER root

RUN apk --no-cache add ca-certificates \
    && rm -rf /var/cache/apk/*

RUN update-ca-certificates

RUN apk --no-cache add curl python3 py3-yaml

USER atlantis
