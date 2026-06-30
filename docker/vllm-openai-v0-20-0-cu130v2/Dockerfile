# ─────────────────────────────────────────────────────────────────────────────
# Authenticated vLLM pod image
#
# Exposes port 8000 (nginx, auth-gated).
# vLLM listens internally on 8001 and is never exposed directly.
#
# Required RunPod env var:
#   API_KEY   – the bearer token callers must supply
#
# Optional RunPod env vars:
#   API_KEY2  – additional accepted bearer token (any of API_KEY/API_KEY2/API_KEY3 works)
#   API_KEY3  – additional accepted bearer token
#               Unset/empty optional keys are replaced with an unguessable
#               random sentinel, so a missing or empty Authorization header
#               can never authenticate.
#   VLLM_ARGS – full vLLM CLI flags (overrides the default Qwen2.5-72B launch)
#               e.g. "--model Qwen/Qwen2.5-7B-Instruct --gpu-memory-utilization 0.95"
# ─────────────────────────────────────────────────────────────────────────────
FROM vllm/vllm-openai:v0.20.0-cu130

ARG DEBIAN_FRONTEND=noninteractive

# Pick a dcgm-exporter version and pin it.
# If you prefer another version, change this in one place.
ARG DCGM_EXPORTER_VERSION=3.3.5

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx gettext-base wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Download dcgm-exporter (static-ish Go binary) and install it
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64)  dcgm_arch="amd64" ;; \
      aarch64) dcgm_arch="arm64" ;; \
      *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    wget -O /tmp/dcgm-exporter.tar.gz \
      "https://github.com/NVIDIA/dcgm-exporter/releases/download/v${DCGM_EXPORTER_VERSION}/dcgm-exporter_${DCGM_EXPORTER_VERSION}_linux_${dcgm_arch}.tar.gz"; \
    tar -C /usr/local/bin -xzf /tmp/dcgm-exporter.tar.gz dcgm-exporter; \
    rm -f /tmp/dcgm-exporter.tar.gz; \
    chmod +x /usr/local/bin/dcgm-exporter

# Drop the nginx template in place
COPY nginx.conf.template /etc/nginx/nginx.conf.template

# Copy and wire up the entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8000 is the public-facing port nginx listens on.
# 8001 is vLLM — internal only, never mapped.
EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
