# pod1.cpp.al — SaaS failover (RunPod pod offline)

When the RunPod vLLM pod is offline, this config keeps `https://pod1.cpp.al`
answering, backed by a hosted LLM provider (**OpenRouter** or **Anthropic**)
instead of the pod. It is a drop-in replacement for the pod's own nginx config
(`docker/vllm-openai-v0-28-0/nginx.conf.template`) that runs on *our* server.

It deliberately keeps the same public surface — same bearer-token auth, same
`/brave/api/` proxy — so developers' clients keep working with no change except
the model name (see [Model selection](#model-selection)).

## Files

| File | Purpose |
| --- | --- |
| `pod1.cpp.al` | The nginx vhost. Install to `/etc/nginx/sites-available/`. |
| `env.example` | Copy to `/etc/nginx/saas.env` and fill in. |
| `render.sh` | Turns `saas.env` into the two nginx include files. |

## What changed vs the pod config

| Path | Pod (vLLM) | SaaS failover |
| --- | --- | --- |
| `/gpu-metrics` | DCGM metrics | `404` (no GPU) |
| `/brave/api/` | Brave REST proxy | **unchanged** |
| `/brave/mcp` | loopback MCP server | `502` (needs local server) |
| `/v1/*` | vLLM | OpenRouter / Anthropic |
| `/` (everything else) | vLLM | `404` |

Only the last row is the real switch. The Brave REST proxy is a pure outbound
proxy (`api.search.brave.com`), so it works identically from our server. The
two things that *don't* transfer are GPU metrics (no GPU here) and the Brave
MCP endpoint (it depended on a `brave-search-mcp-server` running inside the
pod).

## The env-file caveat (why `render.sh` exists)

nginx **cannot read a `KEY=VALUE` file at runtime.** It can only `include`
files that are already in nginx syntax (directives like `set $name "value";`),
and its `envsubst`-style substitution only happens when a *template* is
rendered ahead of time. So the plan of "keep an env file in `/etc/nginx` and
have the vhost read it" needs one small bridge.

`render.sh` is that bridge. It:

1. reads `/etc/nginx/saas.env` (a plain `KEY=VALUE` list),
2. emits `/etc/nginx/saas-auth.conf` (the bearer-token allowlist + 401),
3. emits `/etc/nginx/saas-keys.conf` (the provider/brave keys as nginx
   `set` directives).

The vhost then `include`s those two files. This mirrors exactly how the pod's
`entrypoint.sh` generates `/tmp/nginx_auth.conf`. To rotate a key: edit the
env file, re-run `render.sh`, reload nginx.

## Setup

```bash
# 1. Install the files.
sudo cp pod1.cpp.al /etc/nginx/sites-available/pod1.cpp.al.saas
sudo cp render.sh     /etc/nginx/render-saas.sh && sudo chmod +x /etc/nginx/render-saas.sh

# 2. Create the env file (root-only).
sudo cp env.example /etc/nginx/saas.env
sudo chmod 600 /etc/nginx/saas.env
#    ... edit it and fill in API_KEY, BRAVE_API_KEY, and at least one provider key ...

# 3. Render the nginx include files.
sudo /etc/nginx/render-saas.sh

# 4. Swap the active site: disable the transport proxy, enable this one.
sudo rm -f /etc/nginx/sites-enabled/pod1.cpp.al
sudo ln -s /etc/nginx/sites-available/pod1.cpp.al.saas /etc/nginx/sites-enabled/pod1.cpp.al

# 5. Validate and reload.
sudo nginx -t && sudo systemctl reload nginx
```

> The cert is the same domain, so the existing `/etc/letsencrypt/live/...`
> paths and the `.well-known/acme-challenge` location carry over unchanged.

## Choosing a provider

Open `pod1.cpp.al` and look at the `location /v1/` block. **OpenRouter is
enabled by default**; the Anthropic block is commented out directly below it.
To switch, comment out the OpenRouter lines and uncomment the Anthropic lines
(and re-run `nginx -t && systemctl reload nginx`). You only need the key for
the provider you enable.

OpenRouter is the more production-ready default: it speaks the OpenAI wire
format natively and serves `/v1/models`. Anthropic's OpenAI SDK compatibility
layer works but is documented as a testing surface with several features
ignored (see [Limitations](#limitations)).

## Model selection

The model is **specified by the client, in the request body** — the `"model"`
field of `/v1/chat/completions`. nginx passes the JSON body through unchanged
(stock nginx has no way to rewrite a request body), so the model name comes
from whatever the developer's client sends, not from this config.

What differs per provider is the **format** of that model name:

- **Anthropic (OpenAI-compat):** bare Anthropic model ID, no prefix, e.g.
  `"model": "claude-sonnet-4-5"`. Get the current IDs from
  https://platform.claude.com (or the model list).
- **OpenRouter:** provider-prefixed slug, e.g.
  `"model": "anthropic/claude-sonnet-4.6"` or `"model": "openai/gpt-5.2"`.
  You can also use a `~` alias like `"model": "~anthropic/claude-sonnet-latest"`
  to always follow the newest version. Full catalog: https://openrouter.ai/models.

So a client pointed at `https://pod1.cpp.al/v1` with `OPENAI_BASE_URL`-style
settings just changes its model string when we cut over. If you want a
server-side default model (so clients can omit `model`), you'd need a
middleware in front of the provider (e.g. LiteLLM) or an nginx Lua module —
that's out of scope for this config.

## Switching back to the pod

When the pod is back, restore the transport proxy:

```bash
sudo rm -f /etc/nginx/sites-enabled/pod1.cpp.al
sudo ln -s /etc/nginx/sites-available/pod1.cpp.al /etc/nginx/sites-enabled/pod1.cpp.al
sudo nginx -t && sudo systemctl reload nginx
```

(That's the original `templates/pod1.cpp.al/pod1.cpp.al`, with the pod URL in
its `proxy_pass` line.)

## Limitations

- **Model must be set client-side** (nginx can't inject a default model into
  the JSON body). See [Model selection](#model-selection).
- **`/brave/mcp` needs a local `brave-search-mcp-server`** on `127.0.0.1:8080`.
  Until one is installed on our server it returns `502`. To enable it, replace
  the `return 502` block with the same loopback proxy the pod used
  (`proxy_pass http://127.0.0.1:8080/mcp;`, HTTP/1.1, no buffering).
- **Anthropic's OpenAI-compat layer is a testing surface.** It ignores
  `response_format`, `logprobs`, and `strict`; requires `n == 1`; does not
  support prompt caching; and may not serve `/v1/models`. Prefer OpenRouter for
  production failover, or the native Anthropic `/v1/messages` API (a different
  client path this config does not handle).
- **Only the active provider's key is used.** Enable exactly one provider block
  and set its key in `saas.env`.
- **Env values must be nginx-safe.** Don't put `"`, `$`, or `;` in values
  (real API keys don't contain them).
