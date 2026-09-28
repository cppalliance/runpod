#!/bin/bash
# runpodtest2.sh — memory stress test for the vLLM pod (DeepSeek Flash / Pro).
#
# Goal: empirically answer "will this pod hit a fatal OOM under load?" *before*
# it happens in production. It drives a large, concurrent *prefill* — the
# single most memory-hungry thing vLLM does — because prefill is exactly where
# the boot-time OOM (CUDACachingAllocator) would resurface as a fatal error.
#
# If every request returns HTTP 200 with a valid "choices" payload, the pod's
# memory headroom is sufficient for this load. If any request 500s (or hangs),
# the template's --gpu-memory-utilization / --max-num-seqs / speculative tokens
# are too aggressive and must be reduced.
#
# Usage:
#   ./runpodtest2.sh                 # defaults: ~120k tokens, 4 concurrent
#   ./runpodtest2.sh 180000 8        # harder: ~180k tokens, 8 concurrent

# ./runpodtest2.sh            # ~120k tokens, 4 concurrent (baseline)
# ./runpodtest2.sh 180000 8   # ~180k tokens, 8 concurrent (matches --max-num-seqs 8)
# ./runpodtest2.sh 250000 8   # near max-model-len, worst case

#
# What this test does NOT cover (known blind spots):
#   - Long DECODE. MAX_TOKENS=32 stresses prefill only. A long streaming
#     generation (huge max_tokens) or many concurrent reasoning chains stress
#     KV-cache residency over time — a different axis. Not the OOM the boot log
#     pointed at, but worth a separate probe if the workload changes.
#   - High-entropy prompts. This generator produces repetitive, low-entropy
#     text, so tokens are cheaper than the byte count implies. Real code/prose
#     at the same byte size yields MORE tokens; stay aware you're within ~40k
#     tokens of --max-model-len at the top end.
#   - Beyond --max-num-seqs. The hardest run is 8 concurrent = the template's
#     --max-num-seqs. A 9th request is where queueing (or a spike OOM) begins.
#     This pass is a license to keep the current template, NOT to raise
#     --max-num-seqs without re-testing.
#
# Mechanism (why prefill is the right probe):
#   - During prefill vLLM allocates activation/workspace memory proportional
#     to (prompt_tokens × concurrent_sequences), on top of weights + KV cache.
#   - That activation memory is the exact "free: 7MB" headroom that nearly
#     exhausted during boot quantization. Long concurrent prefills consume it
#     for real; if it is too tight, the allocator cannot fall back and the
#     request dies with an OOM (HTTP 500 / hang) instead of a graceful retry.

set -uo pipefail

export POD_URL=https://__
export API_KEY=__

TOKENS_TARGET="${1:-120000}"   # ~ prompt size in tokens (chars ≈ tokens × 4)
CONCURRENCY="${2:-4}"          # simultaneous requests
MAX_TOKENS=32                  # short completion: we stress prefill, not decode
TIMEOUT=900                    # generous; a real OOM errors fast, a hang is itself a failure

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== warmup (captures CUDA graphs so the stress run is representative) =="
curl -sS --max-time 120 -o /dev/null -w "  warmup HTTP %{http_code}\n" \
  "$POD_URL/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"ping"}],"max_tokens":1}' || true

echo "== building ~${TOKENS_TARGET}-token prompt =="
build_prompt() {
  local target_chars=$1
  local unit="The quick brown fox jumps over the lazy dog while the running count is "
  local out="" i=0
  while ((${#out} < target_chars)); do
    out+="${unit}${i} "
    i=$((i + 1))
  done
  printf '%s' "${out:0:target_chars}"
}
chars=$((TOKENS_TARGET * 4))
build_prompt "$chars" > "$TMP/prompt.txt"
echo "  prompt bytes: $(wc -c < "$TMP/prompt.txt")"

# JSON body file. The prompt is single-line spaces/words/digits, so it is
# JSON-safe and can be interpolated directly.
printf '{"messages":[{"role":"user","content":"%s"}],"max_tokens":%d,"stream":false}' \
  "$(cat "$TMP/prompt.txt")" "$MAX_TOKENS" > "$TMP/body.json"

echo "== firing ${CONCURRENCY} concurrent requests =="
for i in $(seq 1 "$CONCURRENCY"); do
  (
    code=$(curl -sS --max-time "$TIMEOUT" -o "$TMP/resp_${i}.json" -w "%{http_code}" \
      "$POD_URL/v1/chat/completions" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d @"$TMP/body.json")
    echo "$code" > "$TMP/code_${i}.txt"
  ) &
done
wait

echo "== results =="
fail=0
for i in $(seq 1 "$CONCURRENCY"); do
  code=$(cat "$TMP/code_${i}.txt")
  if [[ "$code" == "200" ]] && grep -q '"choices"' "$TMP/resp_${i}.json"; then
    pt=$(grep -o '"prompt_tokens":[0-9]*' "$TMP/resp_${i}.json" | head -n1)
    echo "  req $i: OK (HTTP 200)  ${pt:-}"
  else
    echo "  req $i: FAIL (HTTP $code)"
    echo "    body: $(head -c 400 "$TMP/resp_${i}.json")"
    fail=$((fail + 1))
  fi
done

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: all ${CONCURRENCY} requests succeeded — memory headroom is sufficient."
  exit 0
else
  echo "FAIL: ${fail}/${CONCURRENCY} requests failed — reduce --gpu-memory-utilization"
  echo "      (0.93 -> 0.88) and/or --max-num-seqs / speculative tokens."
  exit 1
fi
