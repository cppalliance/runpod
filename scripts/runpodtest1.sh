#!/bin/bash

set -xe

export POD_URL=__
export API_KEY=__

curl -sS "$POD_URL/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Which model are you? Testing the api."}]}'
