"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createApp, computeHmac } = require("../src/app");
const { MemoryStore } = require("../src/store/memory");

const FIXED_NOW = new Date("2026-02-02T12:00:00Z").getTime();

function makeApp(overrides = {}) {
  const store = new MemoryStore();
  const config = {
    hmacSecret: "test-secret",
    hmacMaxSkewSec: 300,
    rateLimit: {
      windowSec: 3600,
      perToken: 30,
      perIp: 120
    },
    ...overrides
  };

  const app = createApp({
    store,
    config,
    now: () => FIXED_NOW
  });

  return { app, store, config };
}

async function call(app, payload) {
  const response = await app.handle({
    method: payload.method || "POST",
    path: payload.path,
    headers: {},
    body: payload.body || "",
    ip: payload.ip || "203.0.113.10"
  });
  return {
    status: response.status,
    json: response.body ? JSON.parse(response.body) : null
  };
}

test("health endpoint responds ok", async () => {
  const { app } = makeApp();
  const result = await call(app, { path: "/v1/health" });
  assert.equal(result.status, 200);
  assert.deepEqual(result.json, { ok: true, status: "ok" });
});

test("register validates fields", async () => {
  const { app } = makeApp();
  const result = await call(app, { path: "/v1/register", body: JSON.stringify({}) });
  assert.equal(result.status, 400);
  assert.equal(result.json.error, "missing_fields");
});

test("register then unregister removes token", async () => {
  const { app, store } = makeApp();
  const token = "apns-token-1";

  const register = await call(app, {
    path: "/v1/register",
    body: JSON.stringify({ token, topic: "com.example.app", env: "sandbox" })
  });
  assert.equal(register.status, 200);

  const stored = await store.getTokenByValue(token);
  assert.equal(stored.token, token);

  const unregister = await call(app, {
    path: "/v1/unregister",
    body: JSON.stringify({ token })
  });
  assert.equal(unregister.status, 200);

  const missing = await store.getTokenByValue(token);
  assert.equal(missing, null);
});

test("wake requires configured hmac", async () => {
  const { app } = makeApp({ hmacSecret: "" });
  const response = await call(app, {
    path: "/v1/wake",
    body: JSON.stringify({ token: "t", ts: 1, proof: "00" })
  });
  assert.equal(response.status, 503);
  assert.equal(response.json.error, "hmac_not_configured");
});

test("wake rejects stale timestamp", async () => {
  const { app } = makeApp();
  const token = "apns-token-2";
  const stale = Math.floor(FIXED_NOW / 1000) - 1000;
  const proof = computeHmac("test-secret", token, stale);
  const response = await call(app, {
    path: "/v1/wake",
    body: JSON.stringify({ token, ts: stale, proof })
  });
  assert.equal(response.status, 401);
  assert.equal(response.json.error, "timestamp_out_of_range");
});

test("wake rejects invalid proof", async () => {
  const { app } = makeApp();
  const token = "apns-token-3";
  const ts = Math.floor(FIXED_NOW / 1000);
  const response = await call(app, {
    path: "/v1/wake",
    body: JSON.stringify({ token, ts, proof: "deadbeef" })
  });
  assert.equal(response.status, 401);
  assert.equal(response.json.error, "invalid_proof");
});

test("wake queues request for valid proof", async () => {
  const { app, store } = makeApp();
  const token = "apns-token-4";

  await call(app, {
    path: "/v1/register",
    body: JSON.stringify({ token, topic: "com.example.app", env: "sandbox" })
  });

  const ts = Math.floor(FIXED_NOW / 1000);
  const proof = computeHmac("test-secret", token, ts);
  const response = await call(app, {
    path: "/v1/wake",
    body: JSON.stringify({ token, ts, proof })
  });

  assert.equal(response.status, 202);
  assert.equal(response.json.status, "queued");
  assert.ok(response.json.wake_id);

  const wake = await store.getWakeRequestById(response.json.wake_id);
  assert.equal(wake.token_id > 0, true);
});

test("rate limit blocks repeated register", async () => {
  const { app } = makeApp({
    rateLimit: { windowSec: 3600, perToken: 1, perIp: 100 }
  });
  const token = "apns-token-5";

  const first = await call(app, {
    path: "/v1/register",
    body: JSON.stringify({ token, topic: "com.example.app", env: "sandbox" })
  });
  assert.equal(first.status, 200);

  const second = await call(app, {
    path: "/v1/register",
    body: JSON.stringify({ token, topic: "com.example.app", env: "sandbox" })
  });
  assert.equal(second.status, 429);
  assert.equal(second.json.error, "rate_limit");
});
