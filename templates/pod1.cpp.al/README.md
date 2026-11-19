# pod1.cpp.al — stable front door for the RunPod pod

## Why this exists

RunPod pods get a new public URL every time they are relaunched (e.g.
`https://<pod-id>-8000.proxy.runpod.net`). Every developer is told that URL
for their `POD_URL`, `ANTHROPIC_BASE_URL`, MCP endpoint, and `BRAVE_API_BASE`
settings — so a relaunched pod means every developer has to update their
config.

`pod1.cpp.al` is a fixed hostname that forwards everything to the pod. When
the pod moves, we change **one `set $pod_upstream` line** here and reload nginx;
developers' configurations never change.

## How it works

This is a **transport** proxy. It does not re-implement the pod's routing or
authentication — the pod's own nginx (see
`docker/vllm-openai-v0-28-0/nginx.conf.template`) remains authoritative for:

- the path split (`/gpu-metrics`, `/brave/api/`, `/brave/mcp`, `/` → everything
  else to vLLM),
- bearer-token auth (per-developer `API_KEY*`),
- the Brave `X-Subscription-Token` injection and MCP key handling.

`pod1.cpp.al` only has to:

1. terminate TLS at our domain,
2. forward every request to the pod, and
3. preserve the connection-level behavior (HTTP/1.1, no buffering, generous
   timeouts) that streaming needs.

Because the front proxy is the *first* hop, those connection-level settings
must be set here too — the pod cannot compensate for a stream that was already
buffered or timed out by the proxy in front of it.

### What names go where

RunPod's proxy routes by hostname (`<pod-id>-8000.proxy.runpod.net`), so the
`Host` header and TLS SNI sent upstream must both be the **RunPod URL** — never
`pod1.cpp.al`. That's why the config sets `Host $proxy_host` and enables
`proxy_ssl_server_name`. Our own hostname survives only in `X-Forwarded-Host`,
which is informational and ignored by routing.

## Setup

1. Point DNS for `pod1.cpp.al` at this server.
2. Copy `pod1.cpp.al` to `/etc/nginx/sites-available/` and symlink:
   ```
   sudo ln -s /etc/nginx/sites-available/pod1.cpp.al /etc/nginx/sites-enabled/
   ```
3. Issue the certificate:
   ```
   sudo certbot --nginx -d pod1.cpp.al
   ```
   (The `.well-known/acme-challenge` location handles the HTTP-01 flow; certbot
   rewrites the `ssl_certificate*` lines to point at `/etc/letsencrypt/live/`.)
4. Edit the `set $pod_upstream` line in the `443` server block, replacing
   `<pod-id>-8000.proxy.runpod.net` with the current pod URL.
5. Validate and reload:
   ```
   sudo nginx -t && sudo systemctl reload nginx
   ```

## When the pod is relaunched

Get the new pod URL from the RunPod console, update the single `set $pod_upstream`
line, then `sudo nginx -t && sudo systemctl reload nginx`. Done.

## Test

```bash
# Auth still enforced by the pod (expect 401 without a token)
curl -s -o /dev/null -w "%{http_code}\n" https://pod1.cpp.al/v1/models

# Real request with a developer token
curl -s https://pod1.cpp.al/v1/models \
  -H "Authorization: Bearer $API_KEY"
```

Both should behave exactly as they did against the pod URL directly.

## Monitoring

The pod image (`docker/vllm-openai-v0-32-0/`) serves an **unauthenticated**
`/healthz` (v0.32.0v2 and later). It passes through this proxy unchanged, so a
monitor needs no API key:

```bash
curl -s https://pod1.cpp.al/healthz        # 200 "ok"
```

The body is fixed text — match it if you like — but the status code already
means something specific:

| Response | Meaning |
|---|---|
| `200 ok` | front nginx, pod nginx, and vLLM's own engine health check all answered |
| `5xx` | pod nginx is up but vLLM's `/health` failed or timed out |
| `502` / `504` from this host | pod nginx unreachable (pod down / relaunched; `$pod_upstream` stale) |

Nagios:

```
check_http -H pod1.cpp.al -S --sni -u /healthz -s ok -t 10
```

Note that vLLM only starts listening after the model loads, so `/healthz` is
`5xx` for the whole model-loading window after a relaunch. Use `max_check_attempts`
generously, or temporarily put the check in a downtime when relaunching.

`/health` (no `z`) is still vLLM's own endpoint behind auth — `/healthz` is the
one meant for monitors, and it is the only unauthenticated path.
