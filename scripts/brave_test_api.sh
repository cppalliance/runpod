#!/bin/bash
# Test the pod's /brave/api/ proxy (raw Brave REST API).
#
# The pod's nginx accepts your personal API_KEY as the Authorization header,
# drops it, and injects the shared real BRAVE_API_KEY as X-Subscription-Token
# on the way to https://api.search.brave.com/res/v1/. See docs/BRAVE.md.
#
# Expected: a JSON object with a "web" key containing "results" (search hits).

set -xe

export POD_URL=https://__
export API_KEY=__

echo "A list of Brave web search results ('web.results') is expected."

curl -sS -G "$POD_URL/brave/api/web/search" \
  --data-urlencode "q=boost C++" \
  --data-urlencode "count=3" \
  -H "Authorization: Bearer $API_KEY"
