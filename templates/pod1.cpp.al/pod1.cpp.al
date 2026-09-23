# pod1.cpp.al — stable front door for the RunPod vLLM pod
#
# The RunPod pod has an ephemeral URL of the form
#
#     https://<pod-id>-8000.proxy.runpod.net
#
# which changes every time RunPod relaunches the pod. This host absorbs that
# churn: clients point at https://pod1.cpp.al, and this nginx forwards every
# request, unchanged, to whatever pod URL is configured below.
#
# When the pod is relaunched, edit the ONE proxy_pass line below and reload:
#
#     sudo systemctl reload nginx
#
# This is a *transport* proxy only. It deliberately does NOT re-declare the
# pod's per-path routing (/gpu-metrics, /brave/mcp, /brave/api/, /v1/...) or
# authentication: the pod's own nginx is authoritative for all of that. The
# only settings that must be repeated here are the connection-level ones
# (HTTP/1.1 + no buffering + generous timeouts), because those describe how
# bytes flow and cannot be compensated for downstream.

# ---- HTTP: redirect everything to HTTPS (path preserved) ----
server {
    listen 80;
    listen [::]:80;
    server_name pod1.cpp.al;

    error_log /var/log/nginx/pod1.log;
    access_log /var/log/nginx/pod1.log;

    location '/.well-known/acme-challenge' {
        default_type "text/plain";
        root /var/www/letsencrypt;
    }

    location / {
        return 301 https://pod1.cpp.al$request_uri;
    }
}

# ---- HTTPS: pass everything through to the pod ----
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name pod1.cpp.al;

    error_log /var/log/nginx/pod1.log;
    access_log /var/log/nginx/pod1.log;

    ssl_certificate     /etc/letsencrypt/live/pod1.cpp.al/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pod1.cpp.al/privkey.pem;

    # The pod URL is referenced here (proxy_pass), for SNI, and for the Host
    # header. RunPod's proxy routes by hostname
    # (<pod-id>-8000.proxy.runpod.net), so Host and SNI MUST be the RunPod
    # URL — never pod1.cpp.al. pod1.cpp.al survives only in
    # X-Forwarded-Host, which is informational and ignored by routing.

    location / {
        # >>> CHANGE THIS ONE LINE when the pod URL changes <<<
        proxy_pass https://<pod-id>-8000.proxy.runpod.net;

        # Host and SNI must name the upstream, not us.
        proxy_set_header    Host                $proxy_host;
        proxy_ssl_server_name on;   # send SNI = <pod-id>-8000.proxy.runpod.net

        # Credentials and forwarding metadata. Authorization must NOT be
        # stripped here — the pod's nginx checks it.
        proxy_set_header    X-Real-IP           $remote_addr;
        proxy_set_header    X-Forwarded-For     $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto   $scheme;
        proxy_set_header    X-Forwarded-Host    $host;   # keep pod1.cpp.al here only

        # The pod serves streamable-HTTP (MCP over SSE) and vLLM streaming
        # (chunked transfer-encoding). Both require HTTP/1.1 and no response
        # buffering at EVERY hop, or long/interleaved streams stall.
        proxy_http_version 1.1;
        proxy_set_header    Connection "";
        proxy_buffering     off;

        # The pod allows up to 1h for MCP and 10m for vLLM dialogs. The pod
        # enforces its own finer-grained per-path limits; this proxy only has
        # to be at least as generous as the longest one, so use 1h globally.
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
