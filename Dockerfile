# syntax=docker/dockerfile:1.28
ARG PHP_VERSION=8.3

# ---- build: resolve and install every tool from tools.json -------------------
FROM php:${PHP_VERSION}-cli-bookworm AS build
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git jq unzip \
 && rm -rf /var/lib/apt/lists/*
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY tools.json /build/tools.json
COPY build/install-tools.sh /build/install-tools.sh
RUN chmod +x /build/install-tools.sh \
 && /build/install-tools.sh /build/tools.json /opt/drevops

# ---- runtime ----------------------------------------------------------------
FROM php:${PHP_VERSION}-cli-bookworm
ARG EXTRA_PACKAGES="openssh-client rsync"
LABEL org.opencontainers.image.title="drevops-pack" \
      org.opencontainers.image.description="All DrevOps tools in one image, behind a single drevops command" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.source="https://github.com/JovianOps/drevops-pack" \
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git jq unzip ${EXTRA_PACKAGES} \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*'
COPY --from=build /opt/drevops /opt/drevops
COPY image/drevops /usr/local/bin/drevops
RUN chmod +x /usr/local/bin/drevops
ENV DREVOPS_PACK_HOME=/opt/drevops
WORKDIR /work
ENTRYPOINT ["drevops"]
CMD ["help"]
