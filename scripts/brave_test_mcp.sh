#!/bin/bash
# Test the pod's /brave/mcp endpoint (Brave web search over MCP).
#
# The pod runs a brave-search-mcp-server behind nginx. This script speaks the
# MCP streamable-HTTP protocol with plain curl:
#   1. initialize  — handshake (returns the server's protocol version)
#   2. tools/call  — invoke brave_web_search for "pie recipes"
#
# Expected: initialized report, then a tools/call result whose content contains
# web search hits for pie recipes. See docs/BRAVE.md.

# Not tested yet

set -xe

export POD_URL=https://__
export API_KEY=__

echo "== initialize == (server protocol version expected)"
curl -sS -N -X POST "$POD_URL/brave/mcp" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl-test","version":"1.0"}}}'

echo ""

echo "== tools/call brave_web_search 'pie recipes' == (search results expected)"
curl -sS -N -X POST "$POD_URL/brave/mcp" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"brave_web_search","arguments":{"query":"pie recipes"}}}'

echo ""
