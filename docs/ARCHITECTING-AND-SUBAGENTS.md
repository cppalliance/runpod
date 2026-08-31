
## Using the pod alongside the Claude models

The [wrapper script](AGENTS.md#wrapper-script) points Claude Code at the pod for
everything, so a wrapper session has only `deepseek-v4-pro` available. This page
sets up a small local router instead: requests naming a pod model go to the pod,
everything else goes to `api.anthropic.com` under your own Claude subscription or
API key. Both are then selectable from `/model` in the same session.

Use the wrapper script instead if you want an all-DeepSeek session with nothing
extra to run.

To be provided by an admin:
POD_URL=
API_KEY=

### 1. Get the router

You need Node.js 18+ (`node --version`) and Claude Code 2.1.196 or newer
(`claude --version`).

The router is a single file with no dependencies. Put it anywhere you keep
long-lived tools; this page uses `~/.local/share/claude-router`.

```bash
mkdir -p ~/.local/share/claude-router
curl -fsSL -o ~/.local/share/claude-router/router.mjs \
  https://raw.githubusercontent.com/cppalliance/runpod/master/docs/claude-router/router.mjs
```

### 2. Configure it

Save this as `~/.local/share/claude-router/config.json`, filling in `$POD_URL`
and `$API_KEY`:

```json
{
  "podUrl": "https://YOUR-POD-8000.proxy.runpod.net",
  "podApiKey": "YOUR_POD_API_KEY",
  "podModels": ["deepseek-v4-pro"],
  "anthropicUrl": "https://api.anthropic.com",
  "host": "127.0.0.1",
  "port": 8787,
  "timeoutMs": 660000
}
```

It holds your pod key, so keep it out of any repository:

```bash
chmod 600 ~/.local/share/claude-router/config.json
```

`podModels` lists the models that go to the pod; a trailing `*` is a prefix
match, e.g. `"deepseek*"`.

### 3. Start it

```bash
node ~/.local/share/claude-router/router.mjs
```

```
claude-router listening on http://127.0.0.1:8787
  pod       https://YOUR-POD-8000.proxy.runpod.net  models: deepseek-v4-pro
  anthropic https://api.anthropic.com (client credentials forwarded untouched)
```

Check it from another terminal before going further — a bad pod URL or key looks
like a broken CLI once Claude Code is pointed here:

```bash
curl -s localhost:8787/_router/health | jq '{ok, pod}'
```

```json
{
  "ok": true,
  "pod": "ok"
}
```

### 4. Point Claude Code at it

Add an `env` block to `~/.claude/settings.json` (or a project's
`.claude/settings.json` to scope it to one repository):

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787",
    "ANTHROPIC_CUSTOM_MODEL_OPTION": "deepseek-v4-pro",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_NAME": "DeepSeek V4 Pro (pod)",
    "ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION": "Self-hosted DeepSeek V4 Pro"
  }
}
```

Do not set `ANTHROPIC_AUTH_TOKEN` or `ANTHROPIC_API_KEY` here: they override your
Claude subscription for every model and disable claude.ai connectors. The router
sends the pod key itself. Likewise leave `ANTHROPIC_DEFAULT_OPUS_MODEL` and its
siblings unset — those are what pin the Claude aliases to DeepSeek in the wrapper
script.

### 5. Check it works

Restart Claude Code. `/model` now lists **DeepSeek V4 Pro (pod)** underneath the
built-in models, and selecting it prints a warning that the model is unrecognized
and a 200k context window is assumed. That is expected.

```bash
claude -p "Reply with exactly: pod-ok" --model deepseek-v4-pro
claude -p "Reply with exactly: anthropic-ok" --model sonnet
```

The router prints one line per request, so you can see where each went:

```
deepseek-v4-pro -> pod 200 2067ms
claude-sonnet-5 -> anthropic 200 1438ms
```

### 6. Keep it running

`~/.config/systemd/user/claude-router.service`:

```ini
[Unit]
Description=claude-router
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/node %h/.local/share/claude-router/router.mjs
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
```

Use the path from `command -v node` if yours is not `/usr/bin/node`.

```bash
systemctl --user daemon-reload
systemctl --user enable --now claude-router
journalctl --user -u claude-router -f
```

Add `loginctl enable-linger $USER` if you work over SSH and want the router
running when you are not logged in.

To undo all of this: `systemctl --user disable --now claude-router`, then remove
the `env` block from `~/.claude/settings.json`.

### Web search

Built-in `WebSearch` is served by Anthropic's API, so it works on the Claude
models and fails while DeepSeek is selected. Install the Brave MCP server as
described in [AGENTS.md](AGENTS.md#web-search-brave-mcp); it works on both.

Do not add the global `WebSearch` deny rule from [INFO.md](INFO.md) here — with
the router, WebSearch is still useful on the Claude models.

### Running more work on the pod

The setting above only adds DeepSeek to the picker. These, in the same `env`
block, move work onto the pod without being asked:

| Variable | Effect |
| --- | --- |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Background work — session titles, summaries, small classification calls |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Subagents (see below) |
| `ANTHROPIC_MODEL` | Makes DeepSeek the default model for the session |

Set all three to `deepseek-v4-pro` and only your own `/model` choice still runs
on Claude.

### Subagents

Subagents are usually where the tokens go, so this is the setting worth changing:

```json
{
  "env": {
    "CLAUDE_CODE_SUBAGENT_MODEL": "deepseek-v4-pro"
  }
}
```

A subagent's own `model:` frontmatter wins over this variable, and a model passed
for a single invocation wins over both. (In Claude Code older than 2.1.251 the
variable came first instead.)

The built-in `Explore` and `Plan` agents ignore the variable. Explore fan-outs are
high-volume, low-judgment work and worth moving deliberately — a user-level agent
of the same name replaces the built-in:

`~/.claude/agents/Explore.md`:

```markdown
---
name: Explore
description: Read-only search agent for broad fan-out searches across the codebase.
model: deepseek-v4-pro
tools: Read, Grep, Glob, Bash
---

You are a read-only search agent. Locate the relevant files and report paths with
short excerpts. Do not modify anything.
```

The same `model:` field pins any individual agent, which is the useful pattern:
mechanical work on the pod, judgment on Claude.

`~/.claude/agents/test-runner.md`:

```markdown
---
name: test-runner
description: Runs the test suite and reports which tests fail, with the relevant output.
model: deepseek-v4-pro
tools: Bash, Read, Grep
---

Run the tests, then report failures with the smallest useful excerpt of output.
```

Watch `journalctl --user -u claude-router -f` while a subagent runs to confirm it
is going to the pod.
