#!/bin/bash
set -euo pipefail

if [ -z "${API_KEY:-}" ]; then
    echo "ERROR: API_KEY environment variable is not set."
    exit 1
fi

# API_KEY2 and API_KEY3 are optional. When unset or empty, substitute an
# unguessable random sentinel so the corresponding "Bearer <key>" comparison
# in nginx can never be satisfied by a real client (in particular, a missing
# Authorization header is the empty string and must not authenticate).
gen_disabled_key() {
    printf '__disabled_%s__' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
}

if [ -z "${API_KEY2:-}" ]; then
    API_KEY2="$(gen_disabled_key)"
fi
if [ -z "${API_KEY3:-}" ]; then
    API_KEY3="$(gen_disabled_key)"
fi
export API_KEY API_KEY2 API_KEY3

mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi \
         /tmp/nginx_uwsgi /tmp/nginx_scgi

envsubst '${API_KEY} ${API_KEY2} ${API_KEY3}' \
    < /etc/nginx/nginx.conf.template > /tmp/nginx.conf

# Start nginx
nginx -c /tmp/nginx.conf

# Start DCGM exporter (GPU metrics) on localhost only
# It will be reachable externally only via nginx proxy /gpu-metrics 
if command -v dcgm-exporter >/dev/null 2>&1; then
    echo "Starting dcgm-exporter on 127.0.0.1:9400"
    dcgm-exporter &
else
    echo "WARNING: dcgm-exporter not found; GPU metrics will not be available."
fi

# ── Monitoring agents ────────────────────────────────────────────────────────
# None of these are allowed to keep the pod from serving, so every failure here
# is a warning rather than an exit.

# node_exporter (host metrics for Prometheus) on localhost only, reachable
# externally via the auth-gated nginx /node-metrics route. Change this to
# 0.0.0.0:9100 if you would rather map 9100 as a RunPod TCP port instead.
if [ -x /usr/local/bin/node_exporter ]; then
    echo "Starting node_exporter on 127.0.0.1:9100 (expected scraper: ${PROMETHEUS_HOST:-unset})"
    /usr/local/bin/node_exporter \
        --web.listen-address=127.0.0.1:9100 \
        --collector.textfile.directory=/var/lib/node_exporter &
else
    echo "WARNING: node_exporter not found; host metrics will not be available."
fi

# NRPE (Nagios agent). allowed_hosts in nrpe.cfg restricts who may query it.
if [ -x /usr/sbin/nrpe ]; then
    echo "Starting nrpe on 0.0.0.0:5666"
    /usr/sbin/nrpe -c /etc/nagios/nrpe.cfg -d \
        || echo "WARNING: nrpe failed to start."
else
    echo "WARNING: nrpe not found; Nagios checks will not be available."
fi

# munin-node. The plugin symlinks baked into the image reflect the machine that
# built it, so re-detect which plugins apply to this pod before starting.
if [ -x /usr/sbin/munin-node ]; then
    if [ -n "${MUNIN_NODE_HOST_NAME:-}" ]; then
        sed -i '/^host_name /d' /etc/munin/munin-node.conf
        echo "host_name ${MUNIN_NODE_HOST_NAME}" >> /etc/munin/munin-node.conf
    fi
    /usr/sbin/munin-node-configure --shell --families=contrib,auto 2>/dev/null \
        | sh >/dev/null 2>&1 || true
    echo "Starting munin-node on 0.0.0.0:4949"
    /usr/sbin/munin-node --config /etc/munin/munin-node.conf \
        || echo "WARNING: munin-node failed to start."
else
    echo "WARNING: munin-node not found; munin graphs will not be available."
fi

# Start vLLM on internal port
exec vllm serve "$@" --port 8001
