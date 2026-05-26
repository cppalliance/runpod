
## Runpod.io vLLM Servers

Configurations to launch runpod.io pods.

## Connecting to the LLMs

After pods have already been launched, each instance will be addressable by POD_URL and API_KEY.  

Example:

```
export POD_URL=https://abc-8000.proxy.runpod.net
export API_KEY=xyz
curl ${POD_URL}/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  -d '{
    "messages": [
      {"role": "user", "content": "Test question, please reply hello world."}
    ],
    "temperature": 0.2
  }'
```

POD_URL and API_KEY will vary and should be provided by the administrator or whoever launched the pods in runpod.io. Each pod will have a different URL, and possible a different API_KEY.

## Administration

This section is for administrators when launching pods in runpod.io.

## Templates

The [templates/](./templates/) directory contains information about generating templates which are used to launch multiple instances. If not already done, create templates. https://console.runpod.io/user/templates

## Docker

The [docker/](./docker/) directory contains Dockerfiles and scripts to build and push images which can then be used by pods. The reason for this customization is to provide API security by running an nginx proxy which forwards requests back to the vLLM instance. Nginx listens on port 8000. The vllm process listens on port 8001. 

Often, it's not necessary to build a docker image or create a template, if the step was already done.

## Debugging

- Optionally expose ports 8000,8001 in runpod. By adding port 8001 the llvm process can be reached directly, bypassing the nginx proxy. 
- add flags: --enable-log-requests --uvicorn-log-level info.  These are in the templates.


