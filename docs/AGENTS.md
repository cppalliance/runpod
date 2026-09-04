
## Agents

Access the runpod pod locally as an agent.

To be provided by an admin:  
POD_URL=  
API_KEY=  
BRAVE_API_KEY= (for web search via MCP, see "Web search" below)  

### Cursor IDE

Instructions:

Install Cursor, or    
Upgrade Cursor to the latest version and restart.  
Don't use an out-of-date version.    

Configure Settings

Cursor->Settings->Models  
Uncheck all other models (optional. if bugs appear).  
Add a model "deepseek-v4-pro".  

Cursor->Settings->Models->API Key  
OpenAI API Key: enable key.  $API_KEY  
Override OpenAI Base URL: enable url. $POD_URL ( ending with /v1. Add /v1 to the URL. )  

### Cursor cli agent

Not possible as of 2026-08. IDE custom models don’t show up in the Agent CLI.

### Claude Code 

Install claude code cli:

```
curl -fsSL https://claude.ai/install.sh | bash
```

This installs the binary to ~/.local/bin/claude and adds it to PATH  
(open a new terminal afterward, then verify with `claude --version`).

#### Web search (Brave MCP)

Claude Code's built-in WebSearch tool is served by Anthropic's API and does
not work against our self-hosted pod: the model keeps trying to search and
gets error after error. The fix is to disable the built-in tool and replace
it with a Brave Search MCP server (we have a Brave account; ask admin for a
BRAVE_API_KEY, free tier is 2,000 searches/month).

Then register the Brave Search MCP server once, for all projects
(requires Node.js 18+ for npx):

```
export BRAVE_API_KEY=__
# Install npx on your OS. For example, linux:  
sudo apt install nodejs npm
```

```
claude mcp add brave-search --scope user \
  -e BRAVE_API_KEY=$BRAVE_API_KEY \
  -e BRAVE_MCP_ENABLED_TOOLS=brave_web_search \
  -- npx -y @brave/brave-search-mcp-server
```

Note: use @brave/brave-search-mcp-server (Brave's official package), not the
archived @modelcontextprotocol/server-brave-search. BRAVE_MCP_ENABLED_TOOLS
limits the server to plain web search; drop that line if you also want the
news/image/video/local search tools.

Verify:

```
claude mcp list    # should show brave-search
claude -p "Use the brave_web_search tool to find today's top C++ news headline"
```

Built-in WebFetch (fetching a specific URL) runs client-side and works fine
with the pod, so it stays enabled.

#### Wrapper script

Create a file in $HOME/.local/bin or /usr/local/bin named claude-code-agent.sh.  
Be sure it's on your $PATH.

```
#!/bin/bash

set -xe

export POD_URL=__
export API_KEY=__

# # optional sanity check (expect 200, not 404)
#   curl -sS -o /dev/null -w "%{http_code}\n" \
#     -X POST "$POD_URL/v1/messages" \
#     -H "Authorization: Bearer $API_KEY" \
#     -H "Content-Type: application/json" \
#     -H "anthropic-version: 2023-06-01" \
#     -d '{"model":"deepseek-v4-pro","max_tokens":16,"messages":[{"role":"user","content":"hi"}]}'
#
# exit 0

export ANTHROPIC_BASE_URL="$POD_URL"
export ANTHROPIC_AUTH_TOKEN="$API_KEY"   # Bearer; prefer this over API_KEY for gateways
export ANTHROPIC_API_KEY="$API_KEY"      # some setups want both
export ANTHROPIC_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-pro
claude --model deepseek-v4-pro --disallowedTools "WebSearch"
```

### Debugging

Confirm the correct URL and KEY:

```
curl ${POD_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "messages": [
      {"role": "user", "content": "Which model are you?"}
    ],
    "temperature": 0.2
  }
```

See [ARCHITECTING-AND-SUBAGENTS.md](ARCHITECTING-AND-SUBAGENTS.md) for more advanced agent options.   
