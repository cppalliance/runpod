#!/bin/bash
set -e

if [ -z "$API_KEY" ]; then
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

if [ -z "$API_KEY2" ]; then
    API_KEY2="$(gen_disabled_key)"
fi
if [ -z "$API_KEY3" ]; then
    API_KEY3="$(gen_disabled_key)"
fi
export API_KEY API_KEY2 API_KEY3

mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi \
         /tmp/nginx_uwsgi /tmp/nginx_scgi

envsubst '${API_KEY} ${API_KEY2} ${API_KEY3}' \
    < /etc/nginx/nginx.conf.template > /tmp/nginx.conf
nginx -c /tmp/nginx.conf

exec vllm serve "$@" --port 8001
