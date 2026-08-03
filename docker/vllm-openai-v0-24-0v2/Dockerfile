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
#   MUNIN_NODE_HOST_NAME
#             – name munin-node reports to the munin server. RunPod pod
#               hostnames are random container IDs, so set this to whatever the
#               pod is called in the munin server's host list.
#
# Monitoring agents (see MONITOR_* / PROMETHEUS_* build args below):
#   nrpe             tcp/5666, needs a RunPod TCP port mapping
#   munin-node       tcp/4949, needs a RunPod TCP port mapping
#   node_exporter    localhost only; scrape /node-metrics on 8000 behind auth
# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: pull dcgm-exporter from NVIDIA's published image
# FROM nvcr.io/nvidia/k8s/dcgm-exporter:4.5.3-4.8.2 AS dcgm
# FROM nvidia/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04 AS dcgm
FROM nvcr.io/nvidia/k8s/dcgm-exporter:4.5.2-4.8.1-ubuntu22.04 AS dcgm

# Stage 2: your existing vLLM image
FROM docker.io/vllm/vllm-openai:v0.24.0

ARG DEBIAN_FRONTEND=noninteractive

# Pick a dcgm-exporter version and pin it.
# If you prefer another version, change this in one place.
# Was this used?
# ARG DCGM_EXPORTER_VERSION=3.3.5

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx gettext-base wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Copy the dcgm-exporter binary from the NVIDIA image
COPY --from=dcgm /usr/bin/dcgm-exporter /usr/local/bin/dcgm-exporter
COPY --from=dcgm /usr/lib/x86_64-linux-gnu/libdcgm*.so* /usr/lib/x86_64-linux-gnu/
COPY --from=dcgm /etc/dcgm-exporter /etc/dcgm-exporter

RUN chmod +x /usr/local/bin/dcgm-exporter

# ─── Monitoring agents ───────────────────────────────────────────────────────
# Which monitoring servers are allowed to reach the agents in this image.
# The defaults are the C++ Alliance servers; override with --build-arg from
# build.sh if you point the pods at a different monitoring host.
ARG MONITOR_HOST=monitor.cppalliance.org
ARG MONITOR_IP=54.193.145.236
ARG PROMETHEUS_HOST=prometheus2.cpp.al
ARG PROMETHEUS_IP=35.193.106.93
ARG NODE_EXPORTER_VERSION=1.11.1

# node_exporter has no allow-list of its own; these are recorded so the pod can
# report which Prometheus is expected to scrape it.
ENV PROMETHEUS_HOST=${PROMETHEUS_HOST} \
    PROMETHEUS_IP=${PROMETHEUS_IP}

# NRPE (Nagios) and munin-node come from the distro. monitoring-plugins supplies
# check_load / check_disk / check_swap; procps supplies free(1) for check_mem.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nagios-nrpe-server monitoring-plugins \
        munin-node munin-plugins-core \
        procps && \
    rm -rf /var/lib/apt/lists/*

COPY nrpe.cfg /etc/nagios/nrpe.cfg
COPY nrpe-checks.cfg /etc/nagios/nrpe.d/checks.cfg
COPY check_mem /usr/lib/nagios/plugins/check_mem
COPY munin-node.conf /etc/munin/munin-node.conf

# Bake the monitoring server into the agent config. Munin matches allow lines as
# regular expressions, so the IP goes in with its dots escaped.
RUN set -eu; \
    sed -i "s|@MONITOR_IP@|${MONITOR_IP}|g; s|@MONITOR_HOST@|${MONITOR_HOST}|g" \
        /etc/nagios/nrpe.cfg; \
    monitor_ip_re="$(printf '%s' "${MONITOR_IP}" | sed 's/\./\\./g')"; \
    sed -i "s|@MONITOR_IP_RE@|${monitor_ip_re}|g" /etc/munin/munin-node.conf; \
    chmod 0644 /etc/nagios/nrpe.cfg /etc/nagios/nrpe.d/checks.cfg \
               /etc/munin/munin-node.conf; \
    chmod 0755 /usr/lib/nagios/plugins/check_mem; \
    mkdir -p /var/run/nagios /var/log/nagios /var/run/munin /var/log/munin; \
    chown nagios:nagios /var/run/nagios /var/log/nagios

# node_exporter ships as a single static binary from GitHub releases.
RUN set -eu; \
    wget -q -O /tmp/node_exporter.tar.gz \
        "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"; \
    tar -xzf /tmp/node_exporter.tar.gz -C /usr/local/bin --strip-components=1 \
        "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter"; \
    rm /tmp/node_exporter.tar.gz; \
    chmod 0755 /usr/local/bin/node_exporter; \
    mkdir -p /var/lib/node_exporter

# Drop the nginx template in place
COPY nginx.conf.template /etc/nginx/nginx.conf.template

# Copy and wire up the entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8000 is the public-facing port nginx listens on.
# 8001 is vLLM — internal only, never mapped.
# 4949 (munin) and 5666 (nrpe) are the monitoring agents that need to be reached
# from outside; node_exporter stays on localhost. EXPOSE alone does not make a
# port reachable — the pod's own port configuration is what maps ports, and it
# cannot be changed later without resetting the pod, so declare them up front.
EXPOSE 8000 4949 5666
ENTRYPOINT ["/entrypoint.sh"]
