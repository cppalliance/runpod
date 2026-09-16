# Brave search

A Brave search api is shared company-wide through the runpod.io pod. A single Brave
subscription key lives on the pod; you never need your own. Everything you need
is the pod URL plus your personal `API_KEY` (ask an admin for one).

The motivations for this design are:  
- Mainly, Brave's own restrictions and limitations: "You may have up to 10 keys per plan." That is not enough to assign everyone their own key.    
- Key rotation, management, and security.   
- Ease of use. No extra keys to provision or revoke.  

## Brave API usage

There are three ways to reach Brave through the pod:

- **[Claude Code](#claude-code)** — the `brave_web_search` MCP tool available
  inside your Claude Code sessions.
- **[Brave API (wg21-paperflow)](#brave-api-wg21-paperflow)** — the raw Brave
  REST API, for code that talks to Brave directly (e.g. a local copy of
  `wg21-paperflow`).
- **[Promptforge](#promptforge)** — the PromptForge Gateway's built-in
  `web_search` tool, configured through `gateway.local.toml`.

---

## Claude Code

### How to use it

You do **not** need a local `BRAVE_API_KEY`. Register the pod's Brave MCP
server once, and Claude Code will use it for web search:

```bash
# (optional) remove an older local brave-search, if you had one:
claude mcp remove brave-search --scope user

export API_KEY=__      # your personal pod API key (from an admin)
export POD_URL=__      # the pod URL
claude mcp add brave-search ${POD_URL}/brave/mcp \
  --transport http --scope user \
  --header "Authorization: Bearer $API_KEY"
```

Verify:

```bash
claude mcp list    # should show brave-search
claude -p "Use the brave_web_search tool to find today's top C++ news headline"
```

### Behind the scenes

Why no local key? Because the only place a real Brave key exists is on the pod.
Your `claude mcp add` command points Claude Code at the pod's `/brave/mcp`
endpoint and authenticates with your personal `API_KEY`. The pod's nginx
checks that key, then forwards the request to a Brave MCP server running on the
pod (on a loopback port only), which is the one holding the shared Brave key.

You don't need to know any of this to use it, but for the curious, here is the
nginx block that makes it work:

```nginx
location /brave/mcp {
    include /tmp/nginx_auth.conf;

    proxy_pass         http://127.0.0.1:8080/mcp;
    proxy_http_version 1.1;
    proxy_set_header   Host          $host;
    proxy_set_header   Authorization "";   # don't leak dev tokens upstream
    proxy_set_header   Connection    "";
    proxy_buffering    off;                # MCP streams over SSE
    proxy_read_timeout 3600s;
}
```

The two important details: `Authorization ""` strips *your* token before the
request leaves nginx (it's meaningful only to the pod), and the MCP server
behind nginx already has the real `BRAVE_API_KEY` in its environment.

---

## Brave API (wg21-paperflow)

### How to use it

For code that calls the Brave REST API directly (e.g. a local copy of
`wg21-paperflow`), point `BRAVE_API_BASE` at the pod instead of Brave, and set
`BRAVE_API_KEY` to your personal pod API key (it is **only** meaningful to the
pod, not to Brave):

```bash
export BRAVE_API_BASE="https://<POD_URL>/brave/api"
export BRAVE_API_KEY="__"    # your personal pod API key (from an admin)
```

`wg21-paperflow` appends `web/search` to `BRAVE_API_BASE`, producing a request
to `https://<POD_URL>/brave/api/web/search` — which the pod turns into a real
Brave search on your behalf.

### Behind the scenes

The pod's nginx sits in front of the real Brave REST API. It takes your request
to `/brave/api/web/search`, rewrites it to `https://api.search.brave.com/res/v1/web/search`,
and — crucially — replaces your token with the real shared Brave key on the way
out:

```nginx
location /brave/api/ {
    include /tmp/nginx_auth.conf;

    proxy_pass            https://api.search.brave.com/res/v1/;
    proxy_ssl_server_name on;
    proxy_set_header      Authorization         "";   # drop dev auth
    proxy_set_header      X-Subscription-Token  "${BRAVE_API_KEY}";
    proxy_read_timeout    30s;
}
```

Again, two details matter: the developer's token never leaves the pod, and the
`X-Subscription-Token` header (the credential Brave actually checks) is
overwritten with the pod's real `BRAVE_API_KEY` before the request goes
upstream.

---

## Promptforge

### How to use it

In PromptForge, only the Gateway talks to Brave; the `web_search` tool proxies
every query through it, so the Brave credential and endpoint live in one place:
the gateway's TOML config, under `[tools.web_search]`. Its `base_url` field
defaults to `https://api.search.brave.com/res/v1` and can be pointed at the pod
instead. In `gateway.local.toml`:

```toml
[tools.web_search]
provider = "brave"
api_key = "${BRAVE_API_KEY}"        # your personal pod API key
base_url = "${BRAVE_API_BASE}"      # https://<POD_URL>/brave/api
```

(or hardcode the pod URL directly in `base_url`). The gateway will then issue
`https://<POD_URL>/brave/api/web/search` requests with the pod key in
`X-Subscription-Token`, which the pod's nginx swaps for the real Brave key —
the same `/brave/api/` proxy flow described in the wg21-paperflow section
above; no new nginx configuration is needed.

One difference from wg21-paperflow: PromptForge reads these values from TOML
rather than directly from the environment. The `${VAR}` references above are
interpolated at config load, and if a referenced variable is unset the load
fails (there is no silent fallback to the default). If you want the "env var
optional, defaults to Brave" behavior, omit `base_url` from the production
config and set it only in a developer's local config.

If you discover Brave API use cases which haven't been covered, let us know. More nginx proxies may be added.   
