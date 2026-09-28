# pod1.cpp.al — SaaS failover (RunPod pod offline)
#
# Drop-in replacement for the pod's own nginx config
# (docker/vllm-openai-v0-28-0/nginx.conf.template) that runs on OUR server.
#
# While the pod is up, keep serving from it via the transport proxy at
# templates/pod1.cpp.al/pod1.cpp.al. When the pod is offline, install THIS
# config instead. It keeps the same public surface — same bearer-token auth,
# same /brave/api/ proxy — but forwards OpenAI-style /v1/* chat requests to a
# hosted LLM provider (OpenRouter or Anthropic's OpenAI-compat endpoint)
# instead of the pod's vLLM.
#
# Files this config includes (generated from /etc/nginx/saas.env by render.sh,
# see README.md in this directory):
#   /etc/nginx/saas-auth.conf   inbound bearer-token allowlist + 401
#   /etc/nginx/saas-keys.conf   provider/brave keys and options (nginx `set`)

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

# ---- HTTPS: auth-gated, provider-backed ----
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name pod1.cpp.al;

    error_log /var/log/nginx/pod1.log;
    access_log /var/log/nginx/pod1.log;

    ssl_certificate     /etc/letsencrypt/live/pod1.cpp.al/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pod1.cpp.al/privkey.pem;

    # Secrets/options, rendered from /etc/nginx/saas.env by render.sh.
    # Defines: $brave_api_key, $anthropic_api_key, $anthropic_workspace,
    #          $openrouter_api_key, $openrouter_referer, $openrouter_title
    include /etc/nginx/saas-keys.conf;

    # ---- GPU metrics: there is no GPU on a SaaS failover ----
    location = /gpu-metrics {
        include /etc/nginx/saas-auth.conf;
        default_type application/json;
        return 404 '{"error":"gpu metrics unavailable in SaaS failover mode"}\n';
    }

    # ---- Brave Search REST API (unchanged from the pod) ----
    # Proxies to https://api.search.brave.com/res/v1/, strips the caller's
    # token, and injects the shared BRAVE_API_KEY on the way upstream. This is
    # a pure outbound proxy, so it works identically from our own server.
    location /brave/api/ {
        include /etc/nginx/saas-auth.conf;

        proxy_pass            https://api.search.brave.com/res/v1/;
        proxy_ssl_server_name on;
        proxy_set_header      Authorization        "";
        proxy_set_header      X-Subscription-Token $brave_api_key;
        proxy_read_timeout    30s;
    }

    # ---- Brave Search MCP ----
    # Unlike the pod, our server does not (yet) run brave-search-mcp-server on
    # 127.0.0.1:8080. Until one is installed, return 502 rather than silently
    # proxying to nothing. See README for how to enable it.
    location /brave/mcp {
        include /etc/nginx/saas-auth.conf;
        default_type application/json;
        return 502 '{"error":"brave mcp unavailable in SaaS failover mode"}\n';
    }

    # ---- OpenAI-style LLM endpoint (/v1/chat/completions, /v1/models, ...) ----
    #
    # The model is chosen CLIENT-SIDE, via the "model" field in the request
    # body. nginx passes the JSON body through unchanged (stock nginx cannot
    # rewrite request bodies), so the developer's client must send the model
    # name for whichever provider is active here. See README "Model selection".
    location /v1/ {
        include /etc/nginx/saas-auth.conf;

        # ============================================================
        # PROVIDER #1: OpenRouter  (recommended — native OpenAI format)
        # ============================================================
        # OpenRouter prefixes its API with /api, so /v1/* -> /api/v1/*.
        proxy_pass              https://openrouter.ai/api/v1/;
        proxy_ssl_server_name   on;
        proxy_set_header        Host          openrouter.ai;
        proxy_set_header        Authorization "Bearer $openrouter_api_key";
        proxy_set_header        HTTP-Referer  $openrouter_referer;
        proxy_set_header        X-Title       $openrouter_title;

        # ============================================================
        # PROVIDER #2: Anthropic  (OpenAI SDK compatibility layer)
        # ============================================================
        # To switch, comment out the OpenRouter block above and uncomment the
        # block below. Anthropic's OpenAI-compat base is /v1/, so /v1/* maps
        # 1:1 onto api.anthropic.com/v1/* (no rewrite needed).
        #
        # proxy_set_header      Host            api.anthropic.com;
        # proxy_set_header      Authorization   "Bearer $anthropic_api_key";
        # # Only needed if the Anthropic key spans multiple workspaces:
        # proxy_set_header      anthropic-workspace-id $anthropic_workspace;
        #
        # proxy_pass            https://api.anthropic.com/v1/;
        # proxy_ssl_server_name on;

        # Streaming (SSE / chunked transfer-encoding). Required at this hop
        # for the same reason as the pod and the transport proxy: a buffered
        # or HTTP/1.0 upstream would stall long or interleaved streams.
        proxy_http_version 1.1;
        proxy_set_header    Connection "";
        proxy_buffering     off;
        proxy_read_timeout  600s;
        proxy_send_timeout  600s;
        chunked_transfer_encoding on;
    }

    # ---- everything else: not served in SaaS failover mode ----
    location / {
        include /etc/nginx/saas-auth.conf;
        default_type application/json;
        return 404 '{"error":"not available in SaaS failover mode"}\n';
    }
}
