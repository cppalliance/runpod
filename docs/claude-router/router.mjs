#!/usr/bin/env node
// claude-router — dispatch Anthropic-API traffic by model name.
//
//   pod models      -> self-hosted vLLM endpoint (Anthropic-compatible /v1/messages)
//   gateway models  -> any other Anthropic-compatible endpoint, with its own key
//                      (e.g. DeepSeek at https://api.deepseek.com/anthropic)
//   everything else -> api.anthropic.com, forwarded byte-for-byte with the
//                      client's own credentials (subscription OAuth included).
//
// Setup and configuration: ../ARCHITECTING-AND-SUBAGENTS.md
// Hosted DeepSeek as a second gateway: ../platform.deepseek.com.md
// Config: ./config.json next to this file, or $CLAUDE_ROUTER_CONFIG
//
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { Readable } from 'node:stream';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const CONFIG_PATH = process.env.CLAUDE_ROUTER_CONFIG || path.join(HERE, 'config.json');

const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
const POD_URL = cfg.podUrl.replace(/\/+$/, '');
const POD_KEY = cfg.podApiKey;
const POD_MODELS = cfg.podModels ?? [];
// Extra Anthropic-compatible gateways, each with its own key, tried after the pod:
//   "gateways": [{ "name": "deepseek", "url": "https://api.deepseek.com/anthropic",
//                  "apiKey": "sk-...", "models": ["deepseek-flash*"] }]
const GATEWAYS = (cfg.gateways ?? []).map((g) => ({
  name: g.name ?? g.url,
  url: g.url.replace(/\/+$/, ''),
  apiKey: g.apiKey,
  models: g.models ?? [],
}));
const ANTHROPIC_URL = (cfg.anthropicUrl ?? 'https://api.anthropic.com').replace(/\/+$/, '');
const PORT = cfg.port ?? 8787;
const HOST = cfg.host ?? '127.0.0.1';
const TIMEOUT_MS = cfg.timeoutMs ?? 660_000;

// A model belongs to a list if it matches an entry exactly, or an entry ending
// in '*' as a prefix (e.g. "deepseek*").
const matches = (model, list) =>
  typeof model === 'string' &&
  list.some((m) => (m.endsWith('*') ? model.startsWith(m.slice(0, -1)) : model === m));

const isPodModel = (model) => matches(model, POD_MODELS);

// Hop-by-hop headers, plus ones the upstream fetch must set for itself.
const DROP_HEADERS = new Set([
  'host', 'connection', 'keep-alive', 'transfer-encoding', 'upgrade',
  'proxy-authorization', 'proxy-connection', 'te', 'trailer',
  'content-length', 'accept-encoding',
]);

function forwardHeaders(incoming, { stripAuth }) {
  const out = {};
  for (const [k, v] of Object.entries(incoming)) {
    const key = k.toLowerCase();
    if (DROP_HEADERS.has(key)) continue;
    if (stripAuth && (key === 'authorization' || key === 'x-api-key')) continue;
    out[key] = Array.isArray(v) ? v.join(', ') : v;
  }
  return out;
}

const readBody = (req) =>
  new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });

function anthropicError(res, status, type, message) {
  const payload = JSON.stringify({ type: 'error', error: { type, message } });
  if (!res.headersSent) res.writeHead(status, { 'content-type': 'application/json' });
  res.end(payload);
}

async function health(res) {
  let pod = 'unknown';
  try {
    const r = await fetch(`${POD_URL}/v1/models`, {
      headers: { authorization: `Bearer ${POD_KEY}` },
      signal: AbortSignal.timeout(10_000),
    });
    pod = r.ok ? 'ok' : `http ${r.status}`;
  } catch (e) {
    pod = `unreachable: ${e.message}`;
  }
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ ok: pod === 'ok', podUrl: POD_URL, pod, podModels: POD_MODELS,
                           gateways: GATEWAYS.map((g) => ({ name: g.name, url: g.url, models: g.models })),
                           anthropicUrl: ANTHROPIC_URL, listening: `${HOST}:${PORT}` }, null, 2));
}

const server = http.createServer(async (req, res) => {
  const started = Date.now();
  const url = new URL(req.url, `http://${HOST}:${PORT}`);

  if (url.pathname === '/_router/health') return health(res);

  let body = Buffer.alloc(0);
  try {
    body = await readBody(req);
  } catch {
    return anthropicError(res, 400, 'invalid_request_error', 'could not read request body');
  }

  // Route on the model named in the body; anything unparseable goes to Anthropic.
  let model = null;
  if (body.length) {
    try { model = JSON.parse(body.toString('utf8')).model ?? null; } catch { /* not JSON */ }
  }
  const toPod = isPodModel(model);
  // The pod wins a name it claims; other gateways are tried in config order.
  const gateway = toPod ? null : GATEWAYS.find((g) => matches(model, g.models));
  const upstream = toPod ? 'pod' : gateway ? gateway.name : 'anthropic';

  // The pod and any extra gateway are third parties: they never see the client's
  // Anthropic credentials.
  const headers = forwardHeaders(req.headers, { stripAuth: toPod || Boolean(gateway) });
  let target;
  if (toPod) {
    headers.authorization = `Bearer ${POD_KEY}`;
    target = `${POD_URL}${url.pathname}`; // drop query (?beta=true) — vLLM has no use for it
  } else if (gateway) {
    headers['x-api-key'] = gateway.apiKey;
    target = `${gateway.url}${url.pathname}`; // drop query (?beta=true) too
  } else {
    target = `${ANTHROPIC_URL}${url.pathname}${url.search}`;
  }

  try {
    const upstreamRes = await fetch(target, {
      method: req.method,
      headers,
      body: ['GET', 'HEAD'].includes(req.method) ? undefined : body,
      redirect: 'manual',
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    const outHeaders = {};
    for (const [k, v] of upstreamRes.headers.entries()) {
      const key = k.toLowerCase();
      if (DROP_HEADERS.has(key) || key === 'content-encoding') continue; // fetch already decoded
      outHeaders[k] = v;
    }
    res.writeHead(upstreamRes.status, outHeaders);
    if (typeof res.flushHeaders === 'function') res.flushHeaders();

    if (upstreamRes.body) {
      for await (const chunk of Readable.fromWeb(upstreamRes.body)) res.write(chunk);
    }
    res.end();
    console.log(`${model ?? url.pathname} -> ${upstream} ${upstreamRes.status} ${Date.now() - started}ms`);
  } catch (err) {
    console.error(`${model ?? url.pathname} -> ${upstream} failed after ${Date.now() - started}ms: ${err.message}`);
    if (!res.headersSent) anthropicError(res, 502, 'api_error', `${upstream} upstream failed: ${err.message}`);
    else res.end();
  }
});

server.requestTimeout = 0;
server.headersTimeout = 0;
server.setTimeout(0);
server.listen(PORT, HOST, () => {
  console.log(`claude-router listening on http://${HOST}:${PORT}`);
  console.log(`  pod       ${POD_URL}  models: ${POD_MODELS.join(', ')}`);
  for (const g of GATEWAYS) {
    console.log(`  gateway   ${g.url}  models: ${g.models.join(', ')}`);
  }
  console.log(`  anthropic ${ANTHROPIC_URL} (client credentials forwarded untouched)`);
});
