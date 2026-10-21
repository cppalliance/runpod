# ─────────────────────────────────────────────────────────────────────────────
# Authenticated vLLM pod image — built on vLLM v0.32.0 for DeepSeek V4.1 Flash
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
#               by any of the API_KEY* bearer tokens above. The same key
#               also backs the /brave/api/ REST proxy (X-Subscription-Token
#               injection) used by local copies of wg21-paperflow.
#   VLLM_ARGS – full vLLM CLI flags (overrides the default launch).
#               For DeepSeek V4.1 Flash, see the recipe at:
#                 https://recipes.vllm.ai/deepseek-ai/DeepSeek-V4.1-Flash
#
# Build:
#   docker buildx build -t cppalliance/vllm-openai:v0.32.0v1 .
#
# Required vLLM 0.31.0+ for DeepSeek V4.1 Flash:
#   --tokenizer-mode deepseek_v41
#   --attention-config '{"backend":"FLASHINFER_MLA_SPARSE_DSV41",...}'
#   --engram-config '{"cpu_offload":true}'
#   --reasoning-parser deepseek_v41
#   --tool-call-parser deepseek_v41
#   --speculative-config '{"method":"dspark",...}'
# ─────────────────────────────────────────────────────────────────────────────

# Stage 1: pull dcgm-exporter from NVIDIA's published image
FROM nvcr.io/nvidia/k8s/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04 AS dcgm

# Stage 2: vLLM v0.32.0 — latest stable, supports DeepSeek V4.1 Flash and
# all its flags (--tokenizer-mode deepseek_v41, --attention-config with
# FLASHINFER_MLA_SPARSE_DSV41, --engram-config, etc.)
FROM docker.io/vllm/vllm-openai:v0.32.0

ARG DEBIAN_FRONTEND=noninteractive

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
