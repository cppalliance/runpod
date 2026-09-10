#!/bin/bash
set -euo pipefail

# How many bearer tokens nginx will accept. Slot 1 is API_KEY; the remaining
# slots are API_KEY2 .. API_KEY${NUM_KEYS}. Issuing one key per person means a
# key can be revoked independently when someone leaves, without rotating
# everyone else's key.
NUM_KEYS=25

# API_KEY is required; the rest are optional.
if [ -z "${API_KEY:-}" ]; then
    echo "ERROR: API_KEY environment variable is not set."
    exit 1
fi

# Optional keys (API_KEY2 .. API_KEY20) may be unset or empty. In that case
# substitute an unguessable random sentinel so the corresponding
# "Bearer <key>" comparison in nginx can never be satisfied by a real client
# (in particular, a missing Authorization header is the empty string and must
# not authenticate).
gen_disabled_key() {
    printf '__disabled_%s__' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
}

# Build the nginx auth snippet: for each key emit
#
#     set $expectedN "Bearer <key>";
#     set $auth_ok 0;
#     if ($http_authorization = $expectedN) { set $auth_ok 1; }
#     ...
#     if ($auth_ok = 0) { return 401 '{"error":"Unauthorized"}\n'; }
#
# Keeping this in the entrypoint (rather than 20 copies in the template) makes
# the key count a single tunable above.
auth_snippet=/tmp/nginx_auth.conf
: > "$auth_snippet"

for n in $(seq 1 "$NUM_KEYS"); do
    if [ "$n" -eq 1 ]; then
        name="API_KEY"
    else
        name="API_KEY${n}"
    fi

    value=$(eval "printf '%s' \"\${${name}:-}\"")
    if [ -z "$value" ]; then
        value=$(gen_disabled_key)
    fi
    printf 'set $expected%s "Bearer %s";\n' "$n" "$value" >> "$auth_snippet"
done

{
    printf 'set $auth_ok 0;\n'
    for n in $(seq 1 "$NUM_KEYS"); do
        printf 'if ($http_authorization = $expected%s) { set $auth_ok 1; }\n' "$n"
    done
} >> "$auth_snippet"
cat >> "$auth_snippet" <<'EOF'
if ($auth_ok = 0) { return 401 '{"error":"Unauthorized"}\n'; }
EOF

mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi \
         /tmp/nginx_uwsgi /tmp/nginx_scgi

# The template has one ${...} placeholder now: the shared Brave API key
# injected by the /brave/api/ location. Substitute ONLY that ($host, $auth_ok,
# etc. are nginx variables and must pass through untouched). Keep the same
# behavior as the API_KEY slots: never fail the pod if BRAVE_API_KEY is unset.
if [ -z "${BRAVE_API_KEY:-}" ]; then
    BRAVE_API_KEY=""
fi
export BRAVE_API_KEY
envsubst '${BRAVE_API_KEY}' \
    < /etc/nginx/nginx.conf.template > /tmp/nginx.conf

# Start nginx
nginx -c /tmp/nginx.conf

# Start the Brave Search MCP server on loopback only. The nginx
# location /brave/mcp provides per-developer auth and proxies to it.
# Skip cleanly if no Brave key is configured (it won't break the pod).
if [ -n "${BRAVE_API_KEY:-}" ]; then
    echo "Starting brave-search-mcp-server on 127.0.0.1:8080"
    BRAVE_MCP_TRANSPORT=http \
    BRAVE_MCP_HOST=127.0.0.1 \
    BRAVE_MCP_PORT=8080 \
    BRAVE_MCP_ENABLED_TOOLS=brave_web_search \
    brave-search-mcp-server &
else
    echo "WARNING: BRAVE_API_KEY not set; /brave/mcp will be unavailable."
fi

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
