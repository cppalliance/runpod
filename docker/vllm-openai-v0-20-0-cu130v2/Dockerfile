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
# Stage 1: pull dcgm-exporter from NVIDIA's published image
# FROM nvcr.io/nvidia/k8s/dcgm-exporter:4.5.3-4.8.2 AS dcgm
FROM nvidia/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04 AS dcgm

# Stage 2: your existing vLLM image
FROM vllm/vllm-openai:v0.20.0-cu130

ARG DEBIAN_FRONTEND=noninteractive

# Pick a dcgm-exporter version and pin it.
# If you prefer another version, change this in one place.
ARG DCGM_EXPORTER_VERSION=3.3.5

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx gettext-base wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy the dcgm-exporter binary from the NVIDIA image
COPY --from=dcgm /usr/bin/dcgm-exporter /usr/local/bin/dcgm-exporter
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
