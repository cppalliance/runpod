#!/usr/bin/env bash
# grab-pod.sh — keep trying to create a large pod; stop and notify on success.
#
# Run it inside tmux/screen (so the beep reaches a terminal and it survives logout):
#   tmux new -s grab './grab-pod.sh'
#
# Prereq: runpodctl configured with an API key (runpodctl config --apiKey <key>).

set -u

set -ex

export RUNPOD_API_KEY=__

TEMPLATE_ID="ds2v4qi9jy"
GPU_TYPE="NVIDIA H200"          # GPU ID for H200 SXM; verify with: runpodctl gpu list
GPU_COUNT=4
VOLUME_GB=1000
VOLUME_PATH="/workspace"
POD_NAME="h200x${GPU_COUNT}-grab-$(date +%Y%m%d%H%M)"   # fixed for this run; used to detect success
INTERVAL=300                    # seconds between attempts
NOTIFY_EMAIL="samuel.d.darwin@gmail.com"
LOG="$HOME/grab-pod.log"

# Output that means "no capacity right now, try again later".
UNAVAILABLE_RE='no longer any instances|no instances|not available|insufficient|capacity'

notify() {  # $1 = subject, $2 = body
  printf '%s\n' "$2" | mail -s "$1" "$NOTIFY_EMAIL"
  for _ in 1 2 3 4 5; do printf '\a'; sleep 0.4; done
}

pod_exists() {
  # --all: the default list shows only running/errored pods, and a pod that is
  # still provisioning must count as success too.
  runpodctl pod list --all --output json 2>/dev/null | grep -q "\"$POD_NAME\""
}

attempt=0
while true; do
  attempt=$((attempt + 1))
  ts=$(date '+%F %T')

  # "|| rc=$?" keeps set -e from killing the loop on an expected no-capacity failure.
  rc=0
  out=$(runpodctl pod create \
          --name "$POD_NAME" \
          --template-id "$TEMPLATE_ID" \
          --gpu-id "$GPU_TYPE" \
          --gpu-count "$GPU_COUNT" \
          --cloud-type SECURE \
          --volume-in-gb "$VOLUME_GB" \
          --volume-mount-path "$VOLUME_PATH" 2>&1) || rc=$?
  echo "[$ts] attempt $attempt rc=$rc: $out" >> "$LOG"

  # Ground truth: does a pod with our name now exist? Never trust output parsing alone,
  # or a missed success means a second $$$/hr pod five minutes later.
  if pod_exists; then
    echo "[$ts] SUCCESS: $POD_NAME exists" | tee -a "$LOG"
    notify "RunPod: got pod ($POD_NAME)" \
      "Pod $POD_NAME created on attempt $attempt at $ts.

runpodctl output:
$out

$(runpodctl pod list 2>&1)"
    exit 0
  fi

  if grep -qiE "$UNAVAILABLE_RE" <<<"$out"; then
    echo "[$ts] no capacity, sleeping ${INTERVAL}s" >> "$LOG"
    sleep "$INTERVAL"
    continue
  fi

  # Anything else (auth error, bad flag, unknown message): stop rather than guess.
  echo "[$ts] UNEXPECTED result, stopping" | tee -a "$LOG"
  notify "RunPod grab script stopped: unexpected result" \
    "Attempt $attempt at $ts, rc=$rc.

$out

Check: runpodctl pod list --all"
  exit 2
done

