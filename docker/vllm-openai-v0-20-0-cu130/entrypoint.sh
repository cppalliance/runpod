#!/bin/bash
set -e

if [ -z "$API_KEY" ]; then
    echo "ERROR: API_KEY environment variable is not set."
    exit 1
fi

mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi \
         /tmp/nginx_uwsgi /tmp/nginx_scgi

envsubst '${API_KEY}' < /etc/nginx/nginx.conf.template > /tmp/nginx.conf
nginx -c /tmp/nginx.conf

exec vllm serve "$@" --port 8001
