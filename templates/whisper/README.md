# Speech-to-Text (faster-whisper) on RunPod

A dedicated voice-transcription endpoint for Talktron / wg21.org, running the
upstream [speaches](https://github.com/speaches-ai/speaches) image
(formerly `faster-whisper-server`) — an OpenAI-compatible server whose
speech-to-text is powered by [faster-whisper](https://github.com/SYSTRAN/faster-whisper).

## Why there is no Dockerfile

The custom Dockerfiles in [`docker/`](../../docker/) exist for exactly one
reason: **vLLM has no built-in authentication**, so they wrap it in an nginx
proxy that enforces a bearer token (`API_KEY`).

faster-whisper does **not** run on vLLM (vLLM is for LLMs; Whisper runs on
CTranslate2), but it also does not need its own Dockerfile — the upstream
speaches image has **native API-key auth**. Setting the `API_KEY` environment
variable makes every HTTP endpoint require `Authorization: Bearer <key>`,
with only `/health`, `/docs`, and `/openapi.json` left public. That is exactly
the gating we build nginx for, included upstream. So: upstream image used
directly, no wrapper.

`fedirz/faster-whisper-server` now redirects to `speaches-ai/speaches`; the
image used here is `ghcr.io/speaches-ai/speaches:latest-cuda-12.6.3`.

## Pod choice

| Setting | Value | Why |
|---|---|---|
| GPU | **NVIDIA T4** (16 GB, community cloud) | Cheapest GPU on RunPod (~$0.09–0.22/hr); 16 GB is ~5x the ~3 GB Whisper needs, so plenty of concurrency headroom |
| Container image | `ghcr.io/speaches-ai/speaches:latest-cuda-12.6.3` | Upstream CUDA build |
| Start command | **leave empty** | The image ships its own `CMD` (`uvicorn speaches.main:create_app`) |
| Exposed port | **8000** | The one port speaches listens on (HTTP) |
| Container disk | 40 GB | Image + venv only; models go on the volume |
| Volume disk | **50 GB** mounted at `/workspace` | Model cache (`HF_HOME=/workspace/hf`). Large-v3 int8 is ~1.5 GB — 50 GB is generous |

No `VLLM_ARGS` and no command flags are needed; everything is configured via
environment variables.

## Environment variables

| Variable | Value | Meaning |
|---|---|---|
| `API_KEY` | admin-supplied | Native bearer-token auth on all `/v1/*` HTTP endpoints |
| `PRELOAD_MODELS` | `["Systran/faster-whisper-large-v3"]` | Download + warm the model at startup (JSON list; models are otherwise lazy-loaded per request) |
| `WHISPER__COMPUTE_TYPE` | `int8` | CTranslate2 int8 weights (~1.5–3 GB); fastest on a T4 |
| `STT_MODEL_TTL` | `-1` | Keep the model resident in VRAM (never unload), for predictable latency |
| `LOG_LEVEL` | `info` | Default is `debug` — noisy |
| `ENABLE_UI` | `false` | This is an API endpoint; disabling Gradio trims deps and startup time |
| `HF_HOME` / `HUGGINGFACE_HUB_CACHE` | `/workspace/hf...` | Persist the model on the pod volume (reuse across restarts) |

`WHISPER__INFERENCE_DEVICE` is left unset so the default `auto` selects CUDA on
the T4.

## Launching

1. Create the template: `https://console.runpod.io/user/templates`, contents of
   [`T4.txt`](./T4.txt).
2. Launch a pod from it, selecting an **NVIDIA T4** on community cloud.
3. Expose **port 8000** as HTTP. This is the address the proxy URL points at.

## Testing

```
export POD_URL=https://xxxx-8000.proxy.runpod.net
export API_KEY=__

curl -o /dev/null -w "%{http_code}\n" "$POD_URL/health"          # public → 200

curl "$POD_URL/v1/audio/transcriptions" \
  -H "Authorization: Bearer $API_KEY" \
  -F file=@recording.mp3 \
  -F model=Systran/faster-whisper-large-v3
```

The endpoint is OpenAI-compatible, so any OpenAI SDK works with
`base_url="$POD_URL/v1"`.

## Notes

- **Model choice.** `Systran/faster-whisper-large-v3` is the accuracy pick for
  standards-meeting audio (technical jargon). If latency matters more, swap
  for `deepdml/faster-whisper-large-v3-turbo-ct2` (~1.6 GB, ~2x faster, ~0.3%
  higher WER).
- **What is NOT gated.** `/health`, `/docs`, `/openapi.json`, and the WebSocket
  Realtime endpoints are mounted *without* the API-key dependency. For the
  transcription endpoint this is fine (HTTP `/v1/audio/transcriptions` is
  gated); just be aware the realtime WS route is not.
- **Non-root user.** The image runs as user `ubuntu` (uid 1000). If the model
  download fails with a `Permission denied` on `/workspace/hf`, the volume is
  root-owned on first mount; make it writable by uid 1000 (or relaunch so
  RunPod applies ownership).
- **Comparison to Will's 3090.** `faster-whisper` large-v3 at int8 is the same
  ~3 GB he measured; a T4 is more than enough for a single-endpoint STT
  service.
