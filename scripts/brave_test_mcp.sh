#!/bin/bash
# Test the pod's /brave/mcp endpoint (Brave web search over MCP).
#
# The pod runs a brave-search-mcp-server behind nginx. This script speaks the
# MCP streamable-HTTP protocol with plain curl:
#   1. initialize                 — handshake; the server returns an
#                                   Mcp-Session-Id response header
#   2. notifications/initialized  — tells the server the client is ready
#   3. tools/call                 — invoke brave_web_search for "pie recipes"
#
# The server is stateful: every request after initialize must carry the
# Mcp-Session-Id header, or it answers "Bad Request: Server not initialized".
#
# Expected: initialize result, then a tools/call result whose content contains
# web search hits for pie recipes. See docs/BRAVE.md.

set -xe

export POD_URL=https://__
export API_KEY=__

headers=$(mktemp)
trap 'rm -f "$headers"' EXIT

echo "== initialize == (server protocol version expected)"
curl -sS -N -X POST "$POD_URL/brave/mcp" \
  -D "$headers" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl-test","version":"1.0"}}}'

echo ""

SESSION_ID=$(grep -i '^mcp-session-id:' "$headers" | cut -d' ' -f2 | tr -d '\r')
echo "session id: $SESSION_ID"

echo "== notifications/initialized == (HTTP 202 expected)"
curl -sS -X POST "$POD_URL/brave/mcp" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -H "MCP-Protocol-Version: 2025-06-18" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  -w 'HTTP %{http_code}\n'

echo "== tools/call brave_web_search 'pie recipes' == (search results expected)"
curl -sS -N -X POST "$POD_URL/brave/mcp" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SESSION_ID" \
  -H "MCP-Protocol-Version: 2025-06-18" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"brave_web_search","arguments":{"query":"pie recipes","count":3}}}'

echo ""
