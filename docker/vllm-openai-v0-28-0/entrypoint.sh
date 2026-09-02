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

# Start vLLM on internal port
exec vllm serve "$@" --port 8001
