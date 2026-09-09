# ─────────────────────────────────────────────────────────────────────────────
# Authenticated vLLM pod image
#
# Exposes port 8000 (nginx, auth-gated).
# vLLM listens internally on 8001 and is never exposed directly.
#
# Required RunPod env var:
#   API_KEY   – the bearer token callers must supply
#
# Optional RunPod env vars (one key per person; revoke by removing it):
#   API_KEY2 .. API_KEY20 – additional accepted bearer tokens (up to 20 total).
#               Any unset/empty optional key is replaced with an unguessable
#               random sentinel, so a missing or empty Authorization header
#               can never authenticate. Leaving a key unset never breaks the
#               pod; only API_KEY is required.
#   BRAVE_API_KEY – the shared Brave Search API key. When set, a centralized
#               brave-search-mcp-server is started on 127.0.0.1:8080 and
#               exposed to developers at https://<pod>/brave/mcp, protected
#               by any of the API_KEY* bearer tokens above.
#   VLLM_ARGS – full vLLM CLI flags (overrides the default Qwen2.5-72B launch)
#               e.g. "--model Qwen/Qwen2.5-7B-Instruct --gpu-memory-utilization 0.95"
# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: pull dcgm-exporter from NVIDIA's published image
# FROM nvcr.io/nvidia/k8s/dcgm-exporter:4.5.3-4.8.2 AS dcgm
# FROM nvidia/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04 AS dcgm
FROM nvcr.io/nvidia/k8s/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04 AS dcgm

# Stage 2: your existing vLLM image
FROM docker.io/vllm/vllm-openai:v0.28.0

ARG DEBIAN_FRONTEND=noninteractive

# Pick a dcgm-exporter version and pin it.
# If you prefer another version, change this in one place.
# Was this used?
# ARG DCGM_EXPORTER_VERSION=3.3.5

# Pin the Brave Search MCP server and the Node.js major it requires, so the
# image is reproducible (no `npx -y @...` at pod startup, which would hit the
# npm registry on every boot).
ARG NODE_MAJOR=22
ARG BRAVE_MCP_VERSION=2.1.3

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
        nginx gettext-base wget && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js via NodeSource (deb.nodesource.com), then the pinned Brave
# Search MCP server from npm.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh && \
    bash /tmp/nodesource_setup.sh && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* /tmp/nodesource_setup.sh && \
    npm install -g "@brave/brave-search-mcp-server@${BRAVE_MCP_VERSION}" && \
    npm cache clean --force

# Copy the dcgm-exporter binary from the NVIDIA image
COPY --from=dcgm /usr/bin/dcgm-exporter /usr/local/bin/dcgm-exporter
COPY --from=dcgm /usr/lib/x86_64-linux-gnu/libdcgm*.so* /usr/lib/x86_64-linux-gnu/
COPY --from=dcgm /etc/dcgm-exporter /etc/dcgm-exporter

RUN chmod +x /usr/local/bin/dcgm-exporter

# Drop the nginx template in place
COPY nginx.conf.template /etc/nginx/nginx.conf.template

# Copy and wire up the entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8000 is the public-facing port nginx listens on.
# 8001 is vLLM — internal only, never mapped.
EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
