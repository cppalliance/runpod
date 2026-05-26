# ─────────────────────────────────────────────────────────────────────────────
# Authenticated vLLM pod image
#
# Exposes port 8000 (nginx, auth-gated).
# vLLM listens internally on 8001 and is never exposed directly.
#
# Required RunPod env var:
#   API_KEY   – the bearer token callers must supply
#
# Optional RunPod env var:
#   VLLM_ARGS – full vLLM CLI flags (overrides the default Qwen2.5-72B launch)
#               e.g. "--model Qwen/Qwen2.5-7B-Instruct --gpu-memory-utilization 0.95"
# ─────────────────────────────────────────────────────────────────────────────
FROM vllm/vllm-openai:v0.20.0-cu130

# Install nginx and envsubst (gettext-base).
# The base image is Ubuntu-derived so apt is available.
RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx gettext-base && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Drop the nginx template in place
COPY nginx.conf.template /etc/nginx/nginx.conf.template

# Copy and wire up the entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8000 is the public-facing port nginx listens on.
# 8001 is vLLM — internal only, never mapped.
EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]

