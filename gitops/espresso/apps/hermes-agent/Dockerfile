FROM nousresearch/hermes-agent:v2026.5.16@sha256:b6e41c155d6bfce5ad83c5d0fec670086db8a43250e4511c9474134be5482d33

ARG KUBECTL_VERSION=v1.31.4
ARG KUBECTL_SHA256=298e19e9c6c17199011404278f0ff8168a7eca4217edad9097af577023a5620f
ARG FLUX_VERSION=2.8.5
ARG FLUX_SHA256=63c178ba938a5443265b2ce02691c005acf4ef6188d4dbb9b9d87333558948c4
ARG HELM_VERSION=v4.1.4
ARG HELM_SHA256=70b2c30a19da4db264dfd68c8a3664e05093a361cefd89572ffb36f8abfa3d09
ARG JQ_VERSION=jq-1.7.1
ARG JQ_SHA256=5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5
ARG GH_VERSION=2.73.0
ARG GH_SHA256=9ebc6b751ee182fdb291ceb2213cc17abb1624b30f6d7a3913097af41f48b1b4
ARG OPENCODE_VERSION=0.0.55
ARG OPENCODE_SHA256=7f1f41203e7920aec48f3e2216d334e9ce8c6d0a7b107ceb758fefa4d4c98025
ARG HIMALAYA_VERSION=1.2.0
ARG HIMALAYA_SHA256=e04e6382e3e664ef34b01afa1a2216113194a2975d2859727647b22d9b36d4e4
ARG RIPGREP_VERSION=15.1.0
ARG RIPGREP_SHA256=1c9297be4a084eea7ecaedf93eb03d058d6faae29bbc57ecdaf5063921491599
ARG YQ_VERSION=v4.45.4
ARG YQ_SHA256=b96de04645707e14a12f52c37e6266832e03c29e95b9b139cddcae7314466e69
ARG STERN_VERSION=1.32.0
ARG STERN_SHA256=4733268b0e7fea48426c594d186be8cbcdb863858e08910451ebe3b1c8286f44
ARG MCPORTER_VERSION=0.9.0
ARG SUMMARIZE_VERSION=0.13.0

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates curl git \
      python3-pip \
      netcat-openbsd socat \
      dnsutils \
      unzip \
      iproute2 \
      file; \
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
    chmod +x /usr/local/bin/jq; \
    curl -fsSL -o /tmp/gh.tar.gz "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz"; \
    echo "${GH_SHA256}  /tmp/gh.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gh.tar.gz -C /tmp; \
    mv /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh /usr/local/bin/gh; \
    chmod +x /usr/local/bin/gh; \
    rm -rf /tmp/gh.tar.gz /tmp/gh_${GH_VERSION}_linux_amd64; \
    curl -fsSL -o /tmp/opencode.tar.gz "https://github.com/opencode-ai/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-x86_64.tar.gz"; \
    echo "${OPENCODE_SHA256}  /tmp/opencode.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/opencode.tar.gz -C /usr/local/bin opencode; \
    chmod +x /usr/local/bin/opencode; \
    rm -f /tmp/opencode.tar.gz; \
    curl -fsSL -o /tmp/himalaya.tgz "https://github.com/pimalaya/himalaya/releases/download/v${HIMALAYA_VERSION}/himalaya.x86_64-linux.tgz"; \
    echo "${HIMALAYA_SHA256}  /tmp/himalaya.tgz" | sha256sum -c -; \
    tar -xzf /tmp/himalaya.tgz -C /usr/local/bin himalaya; \
    chmod +x /usr/local/bin/himalaya; \
    rm -f /tmp/himalaya.tgz; \
    curl -fsSL -o /tmp/ripgrep.tar.gz "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz"; \
    echo "${RIPGREP_SHA256}  /tmp/ripgrep.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/ripgrep.tar.gz -C /tmp; \
    mv /tmp/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl/rg /usr/local/bin/rg; \
    chmod +x /usr/local/bin/rg; \
    rm -rf /tmp/ripgrep.tar.gz /tmp/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl; \
    curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"; \
    echo "${YQ_SHA256}  /usr/local/bin/yq" | sha256sum -c -; \
    chmod +x /usr/local/bin/yq; \
    curl -fsSL -o /tmp/stern.tar.gz "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_amd64.tar.gz"; \
    echo "${STERN_SHA256}  /tmp/stern.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/stern.tar.gz -C /usr/local/bin stern; \
    chmod +x /usr/local/bin/stern; \
    rm -f /tmp/stern.tar.gz; \
    pip install --no-cache-dir --break-system-packages jupyter ipykernel; \
    npm install -g mcporter@${MCPORTER_VERSION} @steipete/summarize@${SUMMARIZE_VERSION}
