# DeepSeek Flash via OpenRouter (openrouter.ai)

Adds `deepseek/deepseek-v4.1-flash` through OpenRouter as a *third* row in the
`/model` picker. It does not replace the direct DeepSeek gateway from
[platform.deepseek.com.md](platform.deepseek.com.md) — both can sit in the picker
at once, so you can switch between the same model billed two different ways
without restarting.

Read [platform.deepseek.com.md](platform.deepseek.com.md) first. Everything there
about the router's `gateways` array, `behavesAs`, and `sanitizeToolSchemas`
applies unchanged; this page is only the delta.

## Why bother, when DeepSeek works

Billing, mostly. DeepSeek is prepaid with no auto-recharge, so the balance is an
errand: it hits zero, every request returns `402`, and someone has to go top it
up. OpenRouter has **Auto Top-Up** — set a threshold and a purchase amount on
[the credits page](https://openrouter.ai/settings/credits) and it charges a saved
card when the balance falls below the line.

Two things follow from that which DeepSeek's platform cannot do:

- **Per-key spending caps.** An OpenRouter key can carry a `limit` and a
  `limit_reset` of daily, weekly or monthly, and requests past it get a `403`.
  This is the answer to giving someone an allowance without handing them the
  account.
- **One shared pool.** An organization funds credits centrally and every key
  draws from it, instead of a balance per person.

The cost is a second hop and a small routing markup, and that OpenRouter may
serve the model from any of several providers unless you pin one.

## 1. Get a key

Create one at [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys);
it starts `sk-or-`. Turn on Auto Top-Up while you are there, or the errand simply
moves to a different website.

## 2. Add a second gateway

OpenRouter speaks the Anthropic Messages format at `https://openrouter.ai/api`
— the same shape the pod and DeepSeek use — but authenticates with a bearer
token rather than `x-api-key`. Hence `"auth": "bearer"`, which is the only new
field. Add it alongside the DeepSeek entry in
`~/.local/share/claude-router/config.json`:

```json
{
  "gateways": [
    {
      "name": "deepseek",
      "url": "https://api.deepseek.com/anthropic",
      "apiKey": "YOUR_DEEPSEEK_API_KEY",
      "models": ["deepseek-flash*"],
      "sanitizeToolSchemas": true
    },
    {
      "name": "openrouter",
      "url": "https://openrouter.ai/api",
      "apiKey": "YOUR_OPENROUTER_API_KEY",
      "auth": "bearer",
      "models": ["deepseek/*"],
      "sanitizeToolSchemas": true
    }
  ]
}
```

Keep the rest of the file as it was. Gateways are tried in order, and nothing
overlaps here: OpenRouter names every model `vendor/model`, so `deepseek/*` can
never catch the bare `deepseek-flash` that belongs to the direct gateway, and the
pod still wins `deepseek-v4-pro` outright.

`deepseek/*` rather than the one model ID is deliberate: with it, adding another
OpenRouter model later is a picker row and nothing else. Add `openai/*`,
`qwen/*` or whatever else you want to reach the same way.

Restart, and check both gateways are listed:

```bash
systemctl --user restart claude-router
journalctl --user -u claude-router -n 6 --no-pager
```

```
claude-router listening on http://127.0.0.1:8787
  pod       https://YOUR-POD-8000.proxy.runpod.net  models: deepseek-v4-pro
  gateway   https://api.deepseek.com/anthropic  models: deepseek-flash* (x-api-key)
  gateway   https://openrouter.ai/api  models: deepseek/* (bearer)
  anthropic https://api.anthropic.com (client credentials forwarded untouched)
```

## 3. Add the third row

A third entry in the same `modelPicker.options` array from
[platform.deepseek.com.md](platform.deepseek.com.md#3-add-the-row-to-the-picker) in ~/.claude/settings.json::

```json
{
  "model": "deepseek/deepseek-v4.1-flash[1m]",
  "label": "DeepSeek Flash (OpenRouter)",
  "description": "deepseek/deepseek-v4.1-flash, billed to OpenRouter credits",
  "behavesAs": "claude-sonnet-4-6"
}
```

Same rules as the other rows: `behavesAs` is what makes it appear at all, and
`[1m]` claims OpenRouter's 1,048,576-token window, which Claude Code strips
before the ID goes upstream.

Restart Claude Code. `/model` now offers the pod, DeepSeek direct, and DeepSeek
via OpenRouter, and the router log says which one each request took:

```
deepseek/deepseek-v4.1-flash -> openrouter 200 1631ms
deepseek-flash -> deepseek 200 1204ms
deepseek-v4-pro -> pod 200 2067ms
```

## Notes

**Provider routing.** OpenRouter serves this model from several hosts, each with
its own price, latency and uptime, and you get whichever it picks unless you pin
one on the model's OpenRouter page. `sanitizeToolSchemas` stays on because
DeepSeek itself is among the possibilities, and its validator is the strict one.

**Not a supported configuration.** OpenRouter's own Claude Code guide says the
integration is "only guaranteed to work with the Anthropic first-party provider"
and that non-Anthropic models are not supported through the Anthropic endpoint.
It does work; it is just not a promise anyone has made. The pod and DeepSeek
direct remain the routes to trust when something behaves strangely.

**Which to pick.** Same weights, two paths. Direct is cheaper and one hop
shorter; OpenRouter refills itself and can cap a key. Having both rows means the
answer can be "whichever is up".

**Billing.** Spend appears at
[openrouter.ai/activity](https://openrouter.ai/activity), filterable by model,
provider and key — not on DeepSeek's usage page, which only sees the direct
gateway.
