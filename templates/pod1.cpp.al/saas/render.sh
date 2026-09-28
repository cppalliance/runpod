#!/usr/bin/env bash
set -euo pipefail

# Render the nginx include files the SaaS failover vhost depends on, from a
# KEY=VALUE env file.
#
#   /etc/nginx/saas-auth.conf   inbound bearer-token allowlist + 401
#   /etc/nginx/saas-keys.conf   provider/brave keys and options (nginx `set`)
#
# Why: nginx cannot read a KEY=VALUE file at runtime. It can only `include`
# files that are already in nginx syntax. This script turns the human-friendly
# env file into those nginx-syntax snippets, exactly the way the pod's
# entrypoint.sh generates /tmp/nginx_auth.conf.
#
# Usage (as root):
#   ./render.sh                 # uses /etc/nginx/saas.env
#   ./render.sh /path/to.env    # use a specific env file
#
# After it runs, validate and reload:
#   sudo nginx -t && sudo systemctl reload nginx

ENV_FILE="${1:-${SAAS_ENV_FILE:-/etc/nginx/saas.env}}"
AUTH_OUT="${SAAS_AUTH_OUT:-/etc/nginx/saas-auth.conf}"
KEYS_OUT="${SAAS_KEYS_OUT:-/etc/nginx/saas-keys.conf}"
NUM_KEYS="${SAAS_NUM_KEYS:-25}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: $ENV_FILE not found." >&2
    echo "Copy env.example to $ENV_FILE, fill it in, then re-run." >&2
    exit 1
fi

# ---- Read KEY=VALUE pairs literally (values are never shell-evaluated). ----
declare -A vars
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"                       # strip Windows CR
    [[ -z "$line" || "$line" == '#'* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    [[ -z "$key" ]] && continue
    # strip one pair of matching surrounding quotes, if present
    if [[ "$value" =~ ^\"(.*)\"$ ]]; then value="${BASH_REMATCH[1]}"; fi
    if [[ "$value" =~ ^\'(.*)\'$ ]]; then value="${BASH_REMATCH[1]}"; fi
    vars["$key"]="$value"
done < "$ENV_FILE"

get() { printf '%s' "${vars[${1}]:-}"; }

# ---- 1) inbound auth allowlist (mirrors the pod's entrypoint.sh) ----
# An unset/empty optional key becomes an unguessable random sentinel so a
# missing/empty Authorization header can never match it.
gen_disabled_key() {
    printf '__disabled_%s__' "$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
}

: > "$AUTH_OUT"
for ((n = 1; n <= NUM_KEYS; n++)); do
    if [[ "$n" -eq 1 ]]; then name="API_KEY"; else name="API_KEY${n}"; fi
    value="$(get "$name")"
    [[ -z "$value" ]] && value="$(gen_disabled_key)"
    printf 'set $expected%s "Bearer %s";\n' "$n" "$value" >> "$AUTH_OUT"
done
{
    printf 'set $auth_ok 0;\n'
    for ((n = 1; n <= NUM_KEYS; n++)); do
        printf 'if ($http_authorization = $expected%s) { set $auth_ok 1; }\n' "$n"
    done
} >> "$AUTH_OUT"
cat >> "$AUTH_OUT" <<'EOF'
if ($auth_ok = 0) { return 401 '{"error":"Unauthorized"}\n'; }
EOF

# ---- 2) outbound provider keys / options ----
referer="$(get OPENROUTER_REFERER)"; [[ -z "$referer" ]] && referer="https://pod1.cpp.al"
title="$(get OPENROUTER_TITLE)";   [[ -z "$title" ]]   && title="pod1.cpp.al"

{
    printf 'set $brave_api_key       "%s";\n' "$(get BRAVE_API_KEY)"
    printf 'set $anthropic_api_key   "%s";\n' "$(get ANTHROPIC_API_KEY)"
    printf 'set $anthropic_workspace "%s";\n' "$(get ANTHROPIC_WORKSPACE_ID)"
    printf 'set $openrouter_api_key  "%s";\n' "$(get OPENROUTER_API_KEY)"
    printf 'set $openrouter_referer  "%s";\n' "$referer"
    printf 'set $openrouter_title    "%s";\n' "$title"
} > "$KEYS_OUT"

chmod 600 "$AUTH_OUT" "$KEYS_OUT" 2>/dev/null || true

echo "Wrote:"
echo "  $AUTH_OUT"
echo "  $KEYS_OUT"
echo
echo "Next:"
echo "  sudo nginx -t && sudo systemctl reload nginx"
