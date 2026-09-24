# DeepSeek Flash (platform.deepseek.com)

Adds DeepSeek's hosted `deepseek-flash` to the `/model` picker, next to the pod's
`deepseek-v4-pro` and the Claude models, so one Claude Code session can switch
between all three.

The router this page extends is built in
[ARCHITECTING-AND-SUBAGENTS.md](ARCHITECTING-AND-SUBAGENTS.md). Read that first
if you have not — this page assumes a working router, a `deepseek-v4-pro` row in
your picker, and the `env` block it describes. The single-model pod setup is in
[AGENTS.md](AGENTS.md).

Unlike the pod, `deepseek-flash` is somebody else's service. DeepSeek bills you
per token against a prepaid balance, and only you hold that key.

## 1. Get an API key and a balance

Sign in at [platform.deepseek.com](https://platform.deepseek.com), create a key
under **API Keys**, then fund it at
[platform.deepseek.com/top_up](https://platform.deepseek.com/top_up).

The API is strictly prepaid: no subscription, and no auto-recharge. When the
balance reaches zero every request returns `402 Insufficient Balance` until you
top up again. The Top up page lists the payment methods your account and region
support, and some accounts are asked to complete real-name verification before a
first top-up — the console prompts if yours is one of them.

## 2. Add the gateway to the router

The router dispatches by model name, so a new model needs a new destination.
Add a `gateways` entry to `~/.local/share/claude-router/config.json`:

```json
{
  "podUrl": "https://YOUR-POD-8000.proxy.runpod.net",
  "podApiKey": "YOUR_POD_API_KEY",
  "podModels": ["deepseek-v4-pro"],
  "gateways": [
    {
      "name": "deepseek",
      "url": "https://api.deepseek.com/anthropic",
      "apiKey": "YOUR_DEEPSEEK_API_KEY",
      "models": ["deepseek-flash*"]
    }
  ],
  "anthropicUrl": "https://api.anthropic.com",
  "host": "127.0.0.1",
  "port": 8787,
  "timeoutMs": 660000
}
```

The file now holds two keys, so keep it readable only by you
(`chmod 600 ~/.local/share/claude-router/config.json`).

Restart the router and confirm it:

```bash
systemctl --user restart claude-router
journalctl --user -u claude-router -n 5 --no-pager
```

The banner should now carry a `gateway` line:

```
claude-router listening on http://127.0.0.1:8787
  pod       https://YOUR-POD-8000.proxy.runpod.net  models: deepseek-v4-pro
  gateway   https://api.deepseek.com/anthropic  models: deepseek-flash*
  anthropic https://api.anthropic.com (client credentials forwarded untouched)
```

If yours does not, your `router.mjs` predates this page. Re-fetch it with the
same `curl` as
[ARCHITECTING-AND-SUBAGENTS.md, step 1](ARCHITECTING-AND-SUBAGENTS.md#1-get-the-router)
and restart.

`deepseek-flash*` is a prefix match, the same rule `podModels` uses: it covers
`deepseek-flash` and any suffixed form. The pod is matched first, so
`deepseek-v4-pro` keeps going to the pod even though both are DeepSeek models.

Behind the scenes, the router drops the Anthropic credentials your session
carries, sets the DeepSeek key as `x-api-key`, and forwards only the model names
you listed. Your Claude subscription and its OAuth credentials never reach
DeepSeek, and the DeepSeek key never reaches Anthropic. `deepseek-v4-pro` and
every other model are untouched.

## 3. Add the row to the picker

`ANTHROPIC_CUSTOM_MODEL_OPTION`, from the other page, holds one model — the pod's.
A second model needs the `modelPicker` setting. Add it to `~/.claude/settings.json`
alongside the existing `env` block:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787",
    "ANTHROPIC_CUSTOM_MODEL_OPTION": "deepseek-v4-pro",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_NAME": "DeepSeek V4 Pro (pod)",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION": "Self-hosted DeepSeek V4 Pro"
  },
  "modelPicker": {
    "options": [
      {
        "model": "deepseek-flash",
        "label": "DeepSeek Flash (hosted)",
        "description": "DeepSeek V4.1 Flash via api.deepseek.com",
        "behavesAs": "claude-sonnet-4-6"
      }
    ]
  }
}
```

`behavesAs` is what makes the row appear at all. Claude Code drops a picker row
whose model its catalog does not know, and no build knows `deepseek-flash`;
naming a model it does know lends that model's client-side handling — prompt
profile, capability and effort defaults. It changes neither the label nor the
model ID sent, so DeepSeek still receives `deepseek-flash`. `claude-sonnet-4-6`
suits it because DeepSeek's endpoint maps `claude-sonnet*` to `deepseek-flash`
anyway. The pod's row needs none of this: `ANTHROPIC_CUSTOM_MODEL_OPTION` skips
the catalog check, and `modelPicker` rows do not.

Put `modelPicker` in `~/.claude/settings.json` even if your `env` block lives in
a project's `.claude/settings.json`: Claude Code reads this key from user and
managed settings only, so a project-level copy is ignored. It needs Claude Code
2.1.242 or newer, and `behavesAs` 2.1.281. `replaceBuiltInOptions` is left off,
so the row is added after the built-in models and the pod row stays put.

## 4. Use it

Restart Claude Code and run `/model`. **DeepSeek Flash (hosted)** appears
underneath the built-in models. If the row is missing, `behavesAs` is the first
thing to check — a row Claude Code cannot place is dropped silently.

```bash
claude -p "Reply with exactly: flash-ok" --model deepseek-flash
claude -p "Reply with exactly: pod-ok" --model deepseek-v4-pro
claude -p "Reply with exactly: anthropic-ok" --model sonnet
```

The router prints one line per request, so you can see where each went:

```
deepseek-flash -> deepseek 200 1204ms
deepseek-v4-pro -> pod 200 2067ms
claude-sonnet-5 -> anthropic 200 1438ms
```

## Notes

**Long sessions.** Claude Code budgets 200K for a model it cannot size. Write the
row's `model` as `deepseek-flash[1m]` for DeepSeek's 1M window instead; the
suffix is stripped before the ID reaches DeepSeek.

**Web search.** DeepSeek's API serves Claude Code's built-in web search itself,
so `WebSearch` works while DeepSeek Flash is selected — unlike the pod, where it
fails. Summarising the results is billed as extra tokens. The Brave MCP server
from [BRAVE.md](BRAVE.md) works on every model and is unaffected.

**Subagents.** `CLAUDE_CODE_SUBAGENT_MODEL` accepts `deepseek-flash` like any
other name, but subagents are the high-volume path and the pod is already paid
for. Keep them on `deepseek-v4-pro` unless the pod is down.

**Billing.** Spend shows up on DeepSeek's own **Usage** page
([platform.deepseek.com/usage](https://platform.deepseek.com/usage)), where
**Export** downloads a per-key CSV breakdown. It does not appear in your Claude
subscription, and DeepSeek's platform has no team members or shared seats — the
account, its balance, and its keys belong to one login.

**Just DeepSeek, no Claude?** Skip the router and point Claude Code straight at
`https://api.deepseek.com/anthropic` with `ANTHROPIC_AUTH_TOKEN` set to your key
— but from a wrapper script like the one in
[AGENTS.md](AGENTS.md#wrapper-script), never `settings.json`, where that
variable would override your Claude subscription for every model.
