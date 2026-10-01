#!/bin/bash
# Test the pod's /brave/api/ proxy (raw Brave REST API).
#
# Sends your personal pod API_KEY the way real Brave clients do (wg21-paperflow,
# PromptForge): as X-Subscription-Token. The pod's nginx checks it, then
# replaces it with the shared real BRAVE_API_KEY on the way to
# https://api.search.brave.com/res/v1/. "Authorization: Bearer $API_KEY" is
# also accepted. See docs/BRAVE.md.
#
# Expected: a JSON object with a "web" key containing "results" (search hits).

set -xe

export POD_URL=https://__
export API_KEY=__

echo "A list of Brave web search results ('web.results') is expected."

curl -sS -G "$POD_URL/brave/api/web/search" \
  --data-urlencode "q=boost C++" \
  --data-urlencode "count=3" \
  -H "X-Subscription-Token: $API_KEY"
