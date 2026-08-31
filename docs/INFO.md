## FAQ

### Q: Can I permanently disable the built-in WebSearch tool?

The wrapper script already passes `--disallowedTools "WebSearch"` to disable
WebSearch for pod sessions (it doesn't work against the self-hosted pod, since
Anthropic's built-in WebSearch is served by their API, not ours).

If you want to disable it **even when using the real Anthropic API** (e.g., you
prefer Brave Search across the board), add a permanent deny to
`~/.claude/settings.json`:

```json
{
  "permissions": {
    "deny": ["WebSearch"]
  }
}
```

**Be aware:** this is global — it disables WebSearch for *all* Claude Code
sessions, whether you're pointed at the pod or at Anthropic's own API. If you
switch back and forth between regular Claude and the pod, skip this and rely on
the wrapper script's `--disallowedTools` flag instead.
