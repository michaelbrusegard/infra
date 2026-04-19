FROM --platform=linux/amd64 ghcr.io/openclaw/openclaw:latest@sha256:9d5f1dfbd5deedc37706c78f745b958ffbe9b4f20840cfb4d49c617a50326902

USER root

ARG KUBECTL_VERSION=v1.31.4
ARG KUBECTL_SHA256=298e19e9c6c17199011404278f0ff8168a7eca4217edad9097af577023a5620f
ARG FLUX_VERSION=2.8.5
ARG FLUX_SHA256=63c178ba938a5443265b2ce02691c005acf4ef6188d4dbb9b9d87333558948c4
ARG HELM_VERSION=v4.1.4
ARG HELM_SHA256=70b2c30a19da4db264dfd68c8a3664e05093a361cefd89572ffb36f8abfa3d09
ARG JQ_VERSION=jq-1.7.1
ARG JQ_SHA256=5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    rm -rf /var/lib/apt/lists/*; \
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c -; \
    chmod +x /usr/local/bin/kubectl; \
    curl -fsSL -o /tmp/flux.tar.gz "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_amd64.tar.gz"; \
    echo "${FLUX_SHA256}  /tmp/flux.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/flux.tar.gz -C /usr/local/bin flux; \
    chmod +x /usr/local/bin/flux; \
    rm -f /tmp/flux.tar.gz; \
    curl -fsSL -o /tmp/helm.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"; \
    echo "${HELM_SHA256}  /tmp/helm.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/helm.tar.gz -C /tmp; \
    mv /tmp/linux-amd64/helm /usr/local/bin/helm; \
    chmod +x /usr/local/bin/helm; \
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64; \
    curl -fsSL -o /usr/local/bin/jq "https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-linux-amd64"; \
    echo "${JQ_SHA256}  /usr/local/bin/jq" | sha256sum -c -; \
    chmod +x /usr/local/bin/jq

USER 1000
